import Foundation
import os

@MainActor
final class PracticePlaybackControlService: PracticePlaybackControlServiceProtocol, PracticeSessionLifecycleProtocol {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "HappyPianistAVP",
        category: "PracticePlaybackControlService"
    )

    private let sleeper: SleeperProtocol
    private let sequencerPlaybackService: PracticeSequencerPlaybackServiceProtocol
    private let playbackSequenceBuilder: any PlaybackSequenceBuildingProtocol
    private let chordAttemptAccumulator: ChordAttemptAccumulatorProtocol
    private let stateStore: PracticeSessionStateStore
    private let audioRecognitionService: PracticeAudioRecognitionServiceProtocol?
    private weak var effectHandler: (any PracticeSessionEffectHandlerProtocol)?
    private let audioRecognitionSuppressDuration: TimeInterval
    private let leadInSeconds: TimeInterval

    private var autoplayTask: Task<Void, Never>?
    private var autoplayTaskGeneration = 0
    private var hasShutdown = false

    init(
        sleeper: SleeperProtocol,
        sequencerPlaybackService: PracticeSequencerPlaybackServiceProtocol,
        playbackSequenceBuilder: any PlaybackSequenceBuildingProtocol,
        chordAttemptAccumulator: ChordAttemptAccumulatorProtocol,
        stateStore: PracticeSessionStateStore,
        audioRecognitionService: PracticeAudioRecognitionServiceProtocol?,
        effectHandler: any PracticeSessionEffectHandlerProtocol,
        audioRecognitionSuppressDuration: TimeInterval,
        leadInSeconds: TimeInterval
    ) {
        self.sleeper = sleeper
        self.sequencerPlaybackService = sequencerPlaybackService
        self.playbackSequenceBuilder = playbackSequenceBuilder
        self.chordAttemptAccumulator = chordAttemptAccumulator
        self.stateStore = stateStore
        self.audioRecognitionService = audioRecognitionService
        self.effectHandler = effectHandler
        self.audioRecognitionSuppressDuration = audioRecognitionSuppressDuration
        self.leadInSeconds = leadInSeconds
    }

    func shutdown() {
        guard hasShutdown == false else { return }
        hasShutdown = true
        stateStore.autoplayState = .off
        stopTransientWork()
    }

    func stopTransientWork() {
        stopAutoplayTask()
        stopAutoplayAudio()
    }

    func setAutoplayEnabled(_ isEnabled: Bool) {
        if isEnabled {
            guard stateStore.isManualReplayPlaying == false else { return }

            do {
                try sequencerPlaybackService.warmUp()
            } catch {
                stateStore.recordPlaybackError(error)
            }

            stateStore.autoplayState = .playing
            stateStore.autoplayErrorMessage = nil

            let tick = currentStep?.tick ?? 0
            stateStore.isSustainPedalDown = stateStore.pedalTimeline?.isDown(atTick: tick) ?? false
            startAutoplayTaskIfNeeded()
        } else {
            stateStore.autoplayState = .off
            stopAutoplayTask()
            stopAutoplayAudio()
        }
    }

    func playCurrentStepSound(applyRecognitionSuppress: Bool) {
        guard stateStore.isActiveRangeInvalid == false else { return }
        guard let currentStep else { return }
        guard stateStore.activeRange?.contains(stepIndex: stateStore.currentStepIndex) ?? true else { return }
        guard stateStore.audioPlaybackErrorMessage == nil else { return }

        if applyRecognitionSuppress {
            _ = prepareAudioRecognitionSuppressWindowForPlayback()
        }

        let mode = stateStore.activeRoundConfiguration?.handMode ?? .both
        let expectedNotes = mode == .both ? currentStep.notes : currentStep.notes.filter { mode.allows(hand: $0.hand) }
        let velocityByMIDINote = Dictionary(grouping: expectedNotes, by: \.midiNote)
            .compactMapValues { notes in notes.map(\.velocity).max() }
        let noteOns = velocityByMIDINote
            .map { PracticeOneShotNoteOn(midiNote: $0.key, velocity: $0.value) }
            .sorted { $0.midiNote < $1.midiNote }
        guard noteOns.isEmpty == false else { return }

        do {
            try sequencerPlaybackService.playOneShot(
                noteOns: noteOns,
                durationSeconds: 0.35
            )
        } catch {
            stateStore.recordPlaybackError(error)
        }
    }

    func startAutoplayTaskIfNeeded() {
        guard stateStore.isActiveRangeInvalid == false else { return }
        guard stateStore.autoplayState == .playing else { return }
        guard case .guiding = stateStore.state else { return }
        guard stateStore.steps.isEmpty == false else { return }
        guard stateStore.activeRange?.contains(stepIndex: stateStore.currentStepIndex) ?? true else { return }
        guard stateStore.isManualReplayPlaying == false else { return }

        if let error = autoplayStartErrorMessage() {
            stopAutoplayWithError(error)
            return
        }

        guard autoplayTask == nil else { return }

        autoplayTaskGeneration += 1
        let generation = autoplayTaskGeneration

        let timelineSnapshot = stateStore.autoplayTimeline
        let tempoMapSnapshot = stateStore.tempoMap
        let timingBaseTick = currentStep?.tick ?? 0
        stateStore.autoplayTimingBaseTick = timingBaseTick
        stateStore.notationGuideScrollScheduleTaskGeneration = -1

        autoplayTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await runAutoplayTask(
                    generation: generation,
                    timeline: timelineSnapshot,
                    tempoMap: tempoMapSnapshot,
                    timingBaseTick: timingBaseTick
                )
            } catch {
                stateStore.recordPlaybackError(error)
                stopAutoplayWithError(stateStore.audioPlaybackErrorMessage ?? "无法自动播放：播放任务异常。")
            }
        }
    }

    func stopAutoplayTask() {
        autoplayTaskGeneration += 1
        autoplayTask?.cancel()
        autoplayTask = nil

        stateStore.autoplayTimingBaseTick = nil
        stateStore.notationGuideScrollSchedule.removeAll()
        stateStore.notationGuideScrollScheduleTaskGeneration = -1
    }

    func stopAutoplayAudio() {
        sequencerPlaybackService.stop()
    }

    func smoothNotationScrollTick() -> Double? {
        guard stateStore.autoplayState == .playing, autoplayTask != nil else { return nil }
        guard let baseTick = stateStore.autoplayTimingBaseTick else { return nil }

        let schedule = ensureNotationGuideScrollSchedule(baseTick: baseTick)
        let fallbackTick = Double(currentHighlightGuide?.tick ?? baseTick)
        guard schedule.isEmpty == false else { return fallbackTick }

        let nowSeconds = sequencerPlaybackService.currentSeconds()
        guard nowSeconds.isFinite else { return fallbackTick }

        if nowSeconds <= schedule[0].timeSeconds {
            return Double(schedule[0].tick)
        }
        if let last = schedule.last, nowSeconds >= last.timeSeconds {
            return Double(last.tick)
        }

        var low = 0
        var high = schedule.count - 1
        var best = 0
        while low <= high {
            let mid = (low + high) / 2
            if schedule[mid].timeSeconds <= nowSeconds {
                best = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        let currentIndex = min(best, schedule.count - 1)
        let nextIndex = min(currentIndex + 1, schedule.count - 1)
        guard currentIndex != nextIndex else { return Double(schedule[currentIndex].tick) }

        let currentPoint = schedule[currentIndex]
        let nextPoint = schedule[nextIndex]
        let duration = max(0.000_1, nextPoint.timeSeconds - currentPoint.timeSeconds)
        let fraction = max(0, min(1, (nowSeconds - currentPoint.timeSeconds) / duration))
        return Double(currentPoint.tick) + Double(nextPoint.tick - currentPoint.tick) * fraction
    }

    private var currentStep: PracticeStep? {
        guard stateStore.state != .completed else { return nil }
        guard stateStore.steps.indices.contains(stateStore.currentStepIndex) else { return nil }
        return stateStore.steps[stateStore.currentStepIndex]
    }

    private var currentHighlightGuide: PianoHighlightGuide? {
        guard let index = stateStore.currentHighlightGuideIndex else { return nil }
        guard stateStore.highlightGuides.indices.contains(index) else { return nil }
        return stateStore.highlightGuides[index]
    }

    private func autoplayStartErrorMessage() -> String? {
        guard stateStore.pedalTimeline != nil else {
            return "无法自动播放：缺少踏板信息。请重新导入这份 MusicXML。"
        }
        guard stateStore.fermataTimeline != nil else {
            return "无法自动播放：缺少延长停顿（fermata）信息。请重新导入这份 MusicXML。"
        }
        guard stateStore.highlightGuides.isEmpty == false else {
            return "无法自动播放：缺少键盘高亮引导数据。请重新导入这份 MusicXML。"
        }
        guard stateStore.strictTriggerGuideIndex(forStepIndex: stateStore.currentStepIndex) != nil else {
            return "无法自动播放：引导数据不一致（找不到当前步骤的触发点）。请重新导入这份 MusicXML。"
        }
        return nil
    }

    private func stopAutoplayWithError(_ message: String) {
        stateStore.autoplayState = .off
        stopAutoplayTask()
        stopAutoplayAudio()
        stateStore.autoplayErrorMessage = message
        effectHandler?.handle(effect: .refreshAudioRecognition)
    }

    @discardableResult
    private func prepareAudioRecognitionSuppressWindowForPlayback() -> Date {
        let suppressUntil = Date.now.addingTimeInterval(audioRecognitionSuppressDuration)
        stateStore.audioRecognitionSuppressUntil = suppressUntil
        audioRecognitionService?.suppressRecognition(
            until: suppressUntil,
            generation: stateStore.audioRecognitionGeneration
        )
        return suppressUntil
    }

    private func runAutoplayTask(
        generation: Int,
        timeline: AutoplayPerformanceTimeline,
        tempoMap: MusicXMLTempoMap,
        timingBaseTick: Int
    ) async throws {
        guard let pedalTimeline = stateStore.pedalTimeline else { return }
        let initialSustainPedalDown = pedalTimeline.isDown(atTick: timingBaseTick)
        stateStore.isSustainPedalDown = initialSustainPedalDown

        do {
            try sequencerPlaybackService.warmUp()
        } catch {
            stateStore.recordPlaybackError(error)
            stopAutoplayWithError(stateStore.audioPlaybackErrorMessage ?? "无法自动播放：音频服务初始化失败。")
            return
        }

        guard Task.isCancelled == false, autoplayTaskGeneration == generation else { return }

        let sequence: PracticeSequencerSequence
        do {
            sequence = try await playbackSequenceBuilder.buildAutoplaySequence(
                timeline: timeline,
                tempoMap: tempoMap,
                startTick: timingBaseTick,
                initialSustainPedalDown: initialSustainPedalDown,
                leadInSeconds: leadInSeconds
            )
        } catch {
            stateStore.recordPlaybackError(error)
            stopAutoplayWithError(stateStore.audioPlaybackErrorMessage ?? "无法自动播放：构建 MIDI 序列失败。")
            return
        }

        guard Task.isCancelled == false, autoplayTaskGeneration == generation else { return }

        do {
            try sequencerPlaybackService.load(sequence: sequence)
            try sequencerPlaybackService.play(fromSeconds: 0)
        } catch {
            stateStore.recordPlaybackError(error)
            stopAutoplayWithError(stateStore.audioPlaybackErrorMessage ?? "无法自动播放：播放服务启动失败。")
            return
        }

        guard Task.isCancelled == false, autoplayTaskGeneration == generation else { return }

        logger.debug(
            "autoplay sequencer started leadIn=\(self.leadInSeconds, privacy: .public)s now=\(self.sequencerPlaybackService.currentSeconds(), privacy: .public)s"
        )

        var cursor = AutoplayTimelineTimeCursor(
            timeline: timeline,
            tickToSeconds: { tempoMap.timeSeconds(atTick: $0) },
            startTick: timingBaseTick,
            leadInSeconds: leadInSeconds
        )

        var pedalCursor = AutoplayTimelinePedalTimeCursor(
            timeline: timeline,
            tickToSeconds: { tempoMap.timeSeconds(atTick: $0) },
            startTick: timingBaseTick,
            initialIsDown: stateStore.isSustainPedalDown,
            leadInSeconds: leadInSeconds
        )

        let sequenceEndSeconds = max(0, sequence.durationSeconds)

        while Task.isCancelled == false, autoplayTaskGeneration == generation {
            guard stateStore.autoplayState == .playing else { break }
            guard case .guiding = stateStore.state else { break }

            let nowSeconds = sequencerPlaybackService.currentSeconds()

            if let isDown = pedalCursor.advance(toSeconds: nowSeconds) {
                stateStore.isSustainPedalDown = isDown
            }

            for event in cursor.advance(toSeconds: nowSeconds) {
                switch event {
                case let .step(index):
                    advanceAutoplayStep(to: index)
                case let .guide(index, _):
                    stateStore.currentHighlightGuideIndex = index
                }
            }

            if nowSeconds >= sequenceEndSeconds, pedalCursor.isFinished, cursor.isFinished {
                break
            }

            try? await sleeper.sleep(for: .milliseconds(33))
        }

        if Task.isCancelled == false, autoplayTaskGeneration == generation {
            sequencerPlaybackService.stop()
        }

        guard autoplayTaskGeneration == generation else { return }
        autoplayTask = nil
    }

    private func advanceAutoplayStep(to stepIndex: Int) {
        guard stateStore.steps.indices.contains(stepIndex) else { return }
        guard stateStore.currentStepIndex != stepIndex else { return }
        chordAttemptAccumulator.reset()
        stateStore.currentStepIndex = stepIndex
        effectHandler?.handle(effect: .refreshAudioRecognition)
    }

    private func ensureNotationGuideScrollSchedule(baseTick: Int) -> [PracticeSessionNotationGuideScrollPoint] {
        if stateStore.notationGuideScrollScheduleTaskGeneration == autoplayTaskGeneration,
           stateStore.notationGuideScrollScheduleBaseTick == baseTick,
           stateStore.notationGuideScrollScheduleTimelineEventCount == stateStore.autoplayTimeline.events.count
        {
            return stateStore.notationGuideScrollSchedule
        }

        let safeBaseTick = max(0, baseTick)
        let baseSeconds = stateStore.tempoMap.timeSeconds(atTick: safeBaseTick)
        let startIndex = stateStore.autoplayTimeline.firstEventIndex(atOrAfter: safeBaseTick)

        var pausePrefixSeconds: TimeInterval = 0
        var points: [PracticeSessionNotationGuideScrollPoint] = []
        points.reserveCapacity(max(16, stateStore.highlightGuides.count))

        for event in stateStore.autoplayTimeline.events[startIndex...] {
            switch event.kind {
            case let .pauseSeconds(seconds):
                pausePrefixSeconds += seconds

            case .advanceGuide:
                points.append(
                    PracticeSessionNotationGuideScrollPoint(
                        timeSeconds: stateStore.tempoMap.timeSeconds(atTick: event.tick) - baseSeconds +
                            pausePrefixSeconds + leadInSeconds,
                        tick: event.tick
                    )
                )

            case .noteOn, .noteOff, .pedalDown, .pedalUp, .advanceStep:
                continue
            }
        }

        stateStore.notationGuideScrollSchedule = points
        stateStore.notationGuideScrollScheduleBaseTick = baseTick
        stateStore.notationGuideScrollScheduleTaskGeneration = autoplayTaskGeneration
        stateStore.notationGuideScrollScheduleTimelineEventCount = stateStore.autoplayTimeline.events.count
        return points
    }
}

private struct AutoplayTimelinePedalTimeCursor: Equatable {
    private struct TimedPedal: Equatable {
        let timeSeconds: TimeInterval
        let isDown: Bool
    }

    private let scheduled: [TimedPedal]
    private var nextIndex: Int
    private var latestIsDown: Bool

    init(
        timeline: AutoplayPerformanceTimeline,
        tickToSeconds: (Int) -> TimeInterval,
        startTick: Int,
        initialIsDown: Bool,
        leadInSeconds: TimeInterval = 0
    ) {
        let baseTick = max(0, startTick)
        let baseSeconds = tickToSeconds(baseTick)

        let startIndex = timeline.firstEventIndex(atOrAfter: baseTick)
        var pausePrefixSeconds: TimeInterval = 0

        var scheduled: [TimedPedal] = []
        scheduled.reserveCapacity(32)

        for event in timeline.events[startIndex...] {
            switch event.kind {
            case let .pauseSeconds(seconds):
                pausePrefixSeconds += seconds

            case .pedalDown:
                scheduled.append(
                    TimedPedal(
                        timeSeconds: tickToSeconds(event.tick) - baseSeconds + pausePrefixSeconds + leadInSeconds,
                        isDown: true
                    )
                )

            case .pedalUp:
                scheduled.append(
                    TimedPedal(
                        timeSeconds: tickToSeconds(event.tick) - baseSeconds + pausePrefixSeconds + leadInSeconds,
                        isDown: false
                    )
                )

            case .noteOn, .noteOff, .advanceStep, .advanceGuide:
                continue
            }
        }

        self.scheduled = scheduled
        nextIndex = 0
        latestIsDown = initialIsDown
    }

    var isFinished: Bool {
        nextIndex >= scheduled.count
    }

    mutating func advance(toSeconds now: TimeInterval) -> Bool? {
        var updated = false
        while nextIndex < scheduled.count, scheduled[nextIndex].timeSeconds <= now {
            latestIsDown = scheduled[nextIndex].isDown
            nextIndex += 1
            updated = true
        }
        return updated ? latestIsDown : nil
    }
}
