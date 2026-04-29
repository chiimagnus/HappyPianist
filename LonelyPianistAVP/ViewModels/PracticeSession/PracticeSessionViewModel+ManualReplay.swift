import Dispatch
import Foundation
import os

extension PracticeSessionViewModel {
    func startManualReplay(with plan: ManualReplayPlan) {
        let shouldResumeRecognitionWhenReplayEnds = isManualReplayPlaying
            ? shouldResumeAudioRecognitionAfterManualReplay
            : isAudioRecognitionRunning
        stopManualReplayTask(restoreAudioRecognition: false)
        guard plan.stepRange.isEmpty == false else { return }
        guard steps.indices.contains(plan.stepRange.lowerBound) else { return }
        shouldResumeAudioRecognitionAfterManualReplay = shouldResumeRecognitionWhenReplayEnds
        stopAudioRecognition()
        feedbackResetTask?.cancel()
        feedbackResetTask = nil
        feedbackState = .none
        manualReplayGeneration += 1
        let generation = manualReplayGeneration
        let startIndex = plan.stepRange.lowerBound
        let stepRangeSnapshot = plan.stepRange
        let stepsSnapshot = steps
        let tempoMapSnapshot = tempoMap
        isManualReplayPlaying = true
        moveToStep(startIndex, shouldPlaySound: false)
        manualReplayTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var completedReplay = false
            defer {
                if self.manualReplayGeneration == generation {
                    if completedReplay, self.steps.indices.contains(startIndex) {
                        self.currentStepIndex = startIndex
                        self.state = .guiding(stepIndex: startIndex)
                        self.setCurrentHighlightGuideForStepIndex(startIndex)
                    }
                    self.manualReplayTask = nil
                    self.isManualReplayPlaying = false
                    if self.shouldResumeAudioRecognitionAfterManualReplay {
                        self.refreshAudioRecognitionForCurrentState()
                    }
                    self.shouldResumeAudioRecognitionAfterManualReplay = false
                }
            }

            do {
                try sequencerPlaybackService.warmUp()
            } catch {
                recordPlaybackError(error)
                return
            }

            let sequence: PracticeSequencerSequence
            do {
                sequence = try await withCheckedThrowingContinuation { continuation in
                    DispatchQueue.global(qos: .userInitiated).async {
                        do {
                            let builder = PracticeManualReplaySequenceBuilder()
                            continuation.resume(returning: try builder.buildSequence(
                                steps: stepsSnapshot,
                                tempoMap: tempoMapSnapshot,
                                stepRange: stepRangeSnapshot
                            ))
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                }
            } catch {
                recordPlaybackError(error)
                return
            }

            do {
                sequencerPlaybackService.stop()
                try sequencerPlaybackService.load(sequence: sequence)
                try sequencerPlaybackService.play(fromSeconds: 0)
            } catch {
                recordPlaybackError(error)
                return
            }

            var cursor = ManualReplayTimeCursor(
                steps: stepsSnapshot,
                tempoMap: tempoMapSnapshot,
                stepRange: stepRangeSnapshot
            )
            let sequenceEndSeconds = max(0, sequence.durationSeconds)

            while Task.isCancelled == false {
                guard isManualReplayPlaying else { break }
                let nowSeconds = sequencerPlaybackService.currentSeconds()

                if let stepIndex = cursor.advance(toSeconds: nowSeconds) {
                    currentStepIndex = stepIndex
                    state = .guiding(stepIndex: stepIndex)
                    setCurrentHighlightGuideForStepIndex(stepIndex)
                }

                if nowSeconds >= sequenceEndSeconds, cursor.isFinished {
                    break
                }

                try? await sleeper.sleep(for: .milliseconds(33))
            }

            if Task.isCancelled == false {
                sequencerPlaybackService.stop()
            }

            completedReplay = true
        }
    }

    func stopManualReplayTask(restoreAudioRecognition: Bool = true) {
        manualReplayGeneration += 1
        manualReplayTask?.cancel()
        manualReplayTask = nil
        if isManualReplayPlaying {
            isManualReplayPlaying = false
            sequencerPlaybackService.stop()
            if restoreAudioRecognition, shouldResumeAudioRecognitionAfterManualReplay {
                refreshAudioRecognitionForCurrentState()
            }
        }
        shouldResumeAudioRecognitionAfterManualReplay = false
    }
}

private struct ManualReplayTimeCursor: Equatable, Sendable {
    private let scheduledStepIndices: [Int]
    private let scheduledSeconds: [TimeInterval]
    private var nextIndex: Int

    var isFinished: Bool {
        nextIndex >= scheduledSeconds.count
    }

    init(steps: [PracticeStep], tempoMap: MusicXMLTempoMap, stepRange: Range<Int>) {
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
            seconds.append(tempoMap.timeSeconds(atTick: steps[index].tick) - baseSeconds)
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
