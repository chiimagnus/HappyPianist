import Foundation
import os

@MainActor
final class PracticeManualReplayCoordinator: PracticeSessionLifecycleProtocol {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "LonelyPianistAVP",
        category: "PracticeManualReplayCoordinator"
    )

    private let sleeper: SleeperProtocol
    private let sequencerPlaybackService: PracticeSequencerPlaybackServiceProtocol
    private let playbackSequenceBuilder: any PlaybackSequenceBuildingProtocol
    private let stateStore: PracticeSessionStateStore
    private weak var effectHandler: (any PracticeSessionEffectHandlerProtocol)?

    private var manualReplayTask: Task<Void, Never>?
    private var hasShutdown = false

    init(
        sleeper: SleeperProtocol,
        sequencerPlaybackService: PracticeSequencerPlaybackServiceProtocol,
        playbackSequenceBuilder: any PlaybackSequenceBuildingProtocol,
        stateStore: PracticeSessionStateStore,
        effectHandler: any PracticeSessionEffectHandlerProtocol
    ) {
        self.sleeper = sleeper
        self.sequencerPlaybackService = sequencerPlaybackService
        self.playbackSequenceBuilder = playbackSequenceBuilder
        self.stateStore = stateStore
        self.effectHandler = effectHandler
    }

    func shutdown() {
        guard hasShutdown == false else { return }
        hasShutdown = true
        stopManualReplayTask(restoreAudioRecognition: false)
    }

    func startManualReplay(with plan: ManualReplayPlan) {
        let shouldResumeRecognitionWhenReplayEnds = stateStore.isManualReplayPlaying
            ? stateStore.shouldResumeAudioRecognitionAfterManualReplay
            : stateStore.isAudioRecognitionRunning

        stopManualReplayTask(restoreAudioRecognition: false)

        guard plan.stepRange.isEmpty == false else { return }
        guard stateStore.steps.indices.contains(plan.stepRange.lowerBound) else { return }

        stateStore.shouldResumeAudioRecognitionAfterManualReplay = shouldResumeRecognitionWhenReplayEnds

        effectHandler?.handle(effect: .stopAudioRecognition)

        stateStore.manualReplayGeneration += 1
        let generation = stateStore.manualReplayGeneration
        let startIndex = plan.stepRange.lowerBound
        let stepRangeSnapshot = plan.stepRange
        let stepsSnapshot = stateStore.steps
        let tempoMapSnapshot = stateStore.tempoMap
        let leadInSeconds: TimeInterval = 0.05

        stateStore.isManualReplayPlaying = true
        stateStore.currentStepIndex = startIndex
        setCurrentHighlightGuideForStepIndex(startIndex)

        manualReplayTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var completedReplay = false
            defer {
                if stateStore.manualReplayGeneration == generation {
                    if completedReplay, stateStore.steps.indices.contains(startIndex) {
                        stateStore.currentStepIndex = startIndex
                        setCurrentHighlightGuideForStepIndex(startIndex)
                    }

                    manualReplayTask = nil
                    stateStore.isManualReplayPlaying = false

                    if stateStore.shouldResumeAudioRecognitionAfterManualReplay {
                        effectHandler?.handle(effect: .refreshAudioRecognition)
                    }
                    stateStore.shouldResumeAudioRecognitionAfterManualReplay = false
                }
            }

            do {
                try sequencerPlaybackService.warmUp()
            } catch {
                stateStore.recordPlaybackError(error)
                return
            }

            guard Task.isCancelled == false, stateStore.manualReplayGeneration == generation else { return }

            let sequence: PracticeSequencerSequence
            do {
                sequence = try await playbackSequenceBuilder.buildManualReplaySequence(
                    steps: stepsSnapshot,
                    tempoMap: tempoMapSnapshot,
                    stepRange: stepRangeSnapshot,
                    leadInSeconds: leadInSeconds
                )
            } catch {
                stateStore.recordPlaybackError(error)
                return
            }

            guard Task.isCancelled == false, stateStore.manualReplayGeneration == generation else { return }

            do {
                sequencerPlaybackService.stop()
                try sequencerPlaybackService.load(sequence: sequence)
                try sequencerPlaybackService.play(fromSeconds: 0)
            } catch {
                stateStore.recordPlaybackError(error)
                return
            }

            logger.debug(
                "manual replay sequencer started leadIn=\(leadInSeconds, privacy: .public)s now=\(sequencerPlaybackService.currentSeconds(), privacy: .public)s"
            )

            var cursor = ManualReplayTimeCursor(
                steps: stepsSnapshot,
                tempoMap: tempoMapSnapshot,
                stepRange: stepRangeSnapshot,
                leadInSeconds: leadInSeconds
            )
            let sequenceEndSeconds = max(0, sequence.durationSeconds)

            while Task.isCancelled == false, stateStore.manualReplayGeneration == generation {
                guard stateStore.isManualReplayPlaying else { break }

                let nowSeconds = sequencerPlaybackService.currentSeconds()

                if let stepIndex = cursor.advance(toSeconds: nowSeconds) {
                    stateStore.currentStepIndex = stepIndex
                    setCurrentHighlightGuideForStepIndex(stepIndex)
                }

                if nowSeconds >= sequenceEndSeconds, cursor.isFinished {
                    break
                }

                try? await sleeper.sleep(for: .milliseconds(33))
            }

            if Task.isCancelled == false, stateStore.manualReplayGeneration == generation {
                sequencerPlaybackService.stop()
            }

            completedReplay = true
        }
    }

    func stopManualReplayTask(restoreAudioRecognition: Bool = true) {
        stateStore.manualReplayGeneration += 1
        manualReplayTask?.cancel()
        manualReplayTask = nil

        if stateStore.isManualReplayPlaying {
            stateStore.isManualReplayPlaying = false
            sequencerPlaybackService.stop()
            if restoreAudioRecognition, stateStore.shouldResumeAudioRecognitionAfterManualReplay {
                effectHandler?.handle(effect: .refreshAudioRecognition)
            }
        }

        stateStore.shouldResumeAudioRecognitionAfterManualReplay = false
    }

    private func setCurrentHighlightGuideForStepIndex(_ stepIndex: Int) {
        guard stateStore.steps.indices.contains(stepIndex) else {
            stateStore.currentHighlightGuideIndex = nil
            return
        }
        stateStore.currentHighlightGuideIndex = stateStore.strictTriggerGuideIndex(forStepIndex: stepIndex)
    }

}

private struct ManualReplayTimeCursor: Equatable {
    private let scheduledStepIndices: [Int]
    private let scheduledSeconds: [TimeInterval]
    private var nextIndex: Int

    var isFinished: Bool {
        nextIndex >= scheduledSeconds.count
    }

    init(
        steps: [PracticeStep],
        tempoMap: MusicXMLTempoMap,
        stepRange: Range<Int>,
        leadInSeconds: TimeInterval = 0
    ) {
        guard stepRange.isEmpty == false, steps.indices.contains(stepRange.lowerBound) else {
            scheduledStepIndices = []
            scheduledSeconds = []
            nextIndex = 0
            return
        }

        let baseTick = steps[stepRange.lowerBound].tick
        let baseSeconds = tempoMap.timeSeconds(atTick: baseTick)

        var indices: [Int] = []
        var seconds: [TimeInterval] = []
        indices.reserveCapacity(stepRange.count)
        seconds.reserveCapacity(stepRange.count)

        for index in stepRange {
            guard steps.indices.contains(index) else { break }
            indices.append(index)
            seconds.append(tempoMap.timeSeconds(atTick: steps[index].tick) - baseSeconds + leadInSeconds)
        }

        scheduledStepIndices = indices
        scheduledSeconds = seconds
        nextIndex = 0
    }

    mutating func advance(toSeconds nowSeconds: TimeInterval) -> Int? {
        var latestIndex: Int?
        while nextIndex < scheduledSeconds.count {
            if nowSeconds + 0.000_5 < scheduledSeconds[nextIndex] { break }
            latestIndex = scheduledStepIndices[nextIndex]
            nextIndex += 1
        }
        return latestIndex
    }
}
