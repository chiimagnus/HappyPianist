import Foundation
import Diagnostics
import MusicXML
import Practice

@MainActor
final class PracticePlaybackControlService {
    private let sleeper: SleeperProtocol
    private let sequencerPlaybackService: PracticeSequencerPlaybackServiceProtocol
    private let playbackSequenceBuilder: any PlaybackSequenceBuildingProtocol
    private let chordAttemptAccumulator: ChordAttemptAccumulatorProtocol
    private let stateStore: PracticeSessionHostState
    private let audioRecognitionService: PracticeAudioRecognitionServiceProtocol?
    private weak var effectHandler: (any PracticeSessionEffectHandlerProtocol)?
    private let audioRecognitionSuppressDuration: TimeInterval
    private let leadInSeconds: TimeInterval
    private let performanceClock: PerformanceClock
    private let diagnosticsReporter: (any DiagnosticsReporting)?
    private let transportReducer = PerformanceTransportReducer()

    private var autoplayTask: Task<Void, Never>?
    private var pendingResetTask: Task<Void, Never>?
    private var transportState = PerformanceTransportReducer.TransportState.idle
    private var requiresResetBeforeLoad = true
    private var playbackPositionSeconds: TimeInterval = 0
    private var playbackPositionCapturedAt: PerformanceMonotonicInstant?
    private var autoplayTimeSchedule: AutoplayTimelineTimeSchedule?
    private var autoplayContactTimeline: PianoKeyContactTimeline?
    private var autoplayGuideSnapshot: [PianoHighlightGuide]?
    private(set) var isAutoplayPaused = false
    private var autoplayPlaybackRate = 1.0
    private var hasShutdown = false
    var onPianoDemonstrationContactTimelineChange: ((Int?, PianoKeyContactTimeline?) -> Void)?

    private var autoplayTaskGeneration: Int {
        transportState.generation
    }

    init(
        sleeper: SleeperProtocol,
        sequencerPlaybackService: PracticeSequencerPlaybackServiceProtocol,
        playbackSequenceBuilder: any PlaybackSequenceBuildingProtocol,
        chordAttemptAccumulator: ChordAttemptAccumulatorProtocol,
        stateStore: PracticeSessionHostState,
        audioRecognitionService: PracticeAudioRecognitionServiceProtocol?,
        effectHandler: any PracticeSessionEffectHandlerProtocol,
        audioRecognitionSuppressDuration: TimeInterval,
        leadInSeconds: TimeInterval,
        performanceClock: PerformanceClock = .live(),
        diagnosticsReporter: (any DiagnosticsReporting)? = nil
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
        self.performanceClock = performanceClock
        self.diagnosticsReporter = diagnosticsReporter
    }

    func shutdown() {
        guard hasShutdown == false else { return }
        hasShutdown = true
        stateStore.autoplayState = .off
        stopTransientWork()
    }

    func stopTransientWork() {
        stopAutoplayTask()
    }

    func pianoDemonstrationTransportTiming() -> PianoDemonstrationTransportTiming? {
        guard stateStore.autoplayState == .playing,
              autoplayTask != nil,
              let capturedAt = playbackPositionCapturedAt,
              let timeSchedule = autoplayTimeSchedule,
              let contactTimeline = autoplayContactTimeline,
              let guides = autoplayGuideSnapshot
        else {
            return nil
        }
        return PianoDemonstrationTransportTiming(
            generation: autoplayTaskGeneration,
            playbackPositionSeconds: playbackPositionSeconds,
            capturedAt: capturedAt,
            isPaused: isAutoplayPaused,
            playbackRate: autoplayPlaybackRate,
            timeSchedule: timeSchedule,
            contactTimeline: contactTimeline,
            guides: guides
        )
    }

    func resetAndFlushOutput() async {
        stateStore.autoplayState = .off
        stopAutoplayTask()
        await pendingResetTask?.value
        await sequencerPlaybackService.stop(
            resetCommands: PerformanceTransportReducer.fullResetCommands
        )
        await sequencerPlaybackService.stopAllLiveNotes()
    }

    func setAutoplayEnabled(_ isEnabled: Bool) {
        if isEnabled {
            guard stateStore.isManualReplayPlaying == false else { return }

            stateStore.autoplayState = .playing
            stateStore.autoplayErrorMessage = nil

            let tick = currentStep?.tick ?? 0
            stateStore.isSustainPedalDown = sustainPedalIsDown(atTick: tick)
            startAutoplayTaskIfNeeded()
        } else {
            stateStore.autoplayState = .off
            stopAutoplayTask()
        }
    }

    func pauseAutoplay() async {
        guard stateStore.autoplayState == .playing,
              autoplayTask != nil,
              isAutoplayPaused == false
        else {
            return
        }
        let generation = autoplayTaskGeneration
        isAutoplayPaused = true
        let seconds = await sequencerPlaybackService.currentSeconds()
        guard autoplayTaskGeneration == generation, isAutoplayPaused else { return }
        recordPlaybackPosition(seconds)
        await sequencerPlaybackService.pause()
    }

    func resumeAutoplay() async throws {
        guard stateStore.autoplayState == .playing,
              autoplayTask != nil,
              isAutoplayPaused
        else {
            return
        }
        let generation = autoplayTaskGeneration
        do {
            try await sequencerPlaybackService.resume()
        } catch {
            guard autoplayTaskGeneration == generation else { return }
            throw error
        }
        guard autoplayTaskGeneration == generation, isAutoplayPaused else { return }
        let seconds = await sequencerPlaybackService.currentSeconds()
        guard autoplayTaskGeneration == generation, isAutoplayPaused else { return }
        recordPlaybackPosition(seconds)
        isAutoplayPaused = false
    }

    func setAutoplayPlaybackRate(_ rate: Double) async throws {
        try await sequencerPlaybackService.setPlaybackRate(rate)
        autoplayPlaybackRate = rate
        if stateStore.autoplayState == .playing, autoplayTask != nil {
            recordPlaybackPosition(await sequencerPlaybackService.currentSeconds())
        }
    }

    func previewCurrentStepPitches(applyRecognitionSuppress: Bool) {
        guard stateStore.isActiveRangeInvalid == false else { return }
        guard let currentStep else { return }
        guard stateStore.activeRange?.contains(stepIndex: stateStore.currentStepIndex) ?? true else { return }
        guard stateStore.playbackErrorMessage == nil else { return }

        if applyRecognitionSuppress {
            _ = prepareAudioRecognitionSuppressWindowForPlayback()
        }

        let mode = stateStore.activeRoundConfiguration?.handMode ?? .both
        let endTick = stateStore.steps.indices.contains(stateStore.currentStepIndex + 1)
            ? stateStore.steps[stateStore.currentStepIndex + 1].tick
            : Int.max
        let planNotes = stateStore.performancePlan?.noteEvents.filter {
            $0.performedOnTick >= currentStep.tick
                && $0.performedOnTick < endTick
                && mode.allows(hand: $0.handAssignment.hand)
        } ?? []
        let commands = Dictionary(grouping: planNotes, by: \.midiNote)
            .values
            .compactMap { notes -> PracticePlaybackCommand? in
                guard let note = notes.max(by: {
                    $0.velocityResolution.velocity < $1.velocityResolution.velocity
                }) else { return nil }
                return PracticePlaybackCommand(
                    sourceEventID: "preview-\(note.id.description)",
                    kind: .noteOn(midi: note.midiNote, velocity: note.velocityResolution.velocity)
                )
            }
            .sorted { lhs, rhs in
                guard case let .noteOn(lhsMIDI, _) = lhs.kind,
                      case let .noteOn(rhsMIDI, _) = rhs.kind
                else { return lhs.sourceEventID < rhs.sourceEventID }
                return lhsMIDI < rhsMIDI
            }
        guard commands.isEmpty == false else { return }

        Task {
            do {
                try await sequencerPlaybackService.playOneShot(
                    commands: commands,
                    durationSeconds: 0.35
                )
            } catch {
                stateStore.recordPlaybackError(error)
            }
        }
    }

    func startAutoplayTaskIfNeeded() {
        startAutoplayTaskIfNeeded(resetBeforeLoad: requiresResetBeforeLoad)
    }

    private func startAutoplayTaskIfNeeded(resetBeforeLoad: Bool) {
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
        guard let performancePlan = stateStore.performancePlan else { return }

        let timingBaseTick = stateStore.notationPositionTick ?? currentStep?.tick ?? 0
        let transition = transportReducer.transition(
            from: transportState,
            at: .start(
                tick: timingBaseTick,
                activeEventIDs: activeEventIDs(at: timingBaseTick)
            )
        )
        transportState = transition.state
        let generation = transportState.generation

        let guideProjectionSnapshot = stateStore.highlightGuides
        let stepProjectionSnapshot = stateStore.steps
        let tempoMapSnapshot = stateStore.tempoMap
        let handModeSnapshot = stateStore.activeRoundConfiguration?.handMode ?? .both
        let activeRangeSnapshot = stateStore.activeRange
        stateStore.notationPositionTick = timingBaseTick
        let measureBoundaryTicks = stateStore.measureSpans.map(\.startTick) + stateStore.measureSpans.suffix(1).map(\.endTick)

        autoplayTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let timelineSnapshot = await AutoplayPerformanceTimeline.buildOffMain(
                plan: performancePlan,
                guideProjection: guideProjectionSnapshot,
                stepProjection: stepProjectionSnapshot,
                tempoMap: tempoMapSnapshot,
                practiceHandMode: handModeSnapshot,
                activeRange: activeRangeSnapshot,
                transportStartTick: timingBaseTick,
                measureBoundaryTicks: measureBoundaryTicks
            )
            guard Task.isCancelled == false, autoplayTaskGeneration == generation else { return }
            stateStore.autoplayTimeline = timelineSnapshot
            timelineSnapshot.recordTransportDiagnostics(
                using: diagnosticsReporter,
                stage: "autoplay.timeline"
            )
            do {
                try await runAutoplayTask(
                    generation: generation,
                    plan: performancePlan,
                    timeline: timelineSnapshot,
                    guides: guideProjectionSnapshot,
                    steps: stepProjectionSnapshot,
                    tempoMap: tempoMapSnapshot,
                    timingBaseTick: timingBaseTick,
                    resetBeforeLoad: resetBeforeLoad
                )
            } catch {
                guard Task.isCancelled == false, autoplayTaskGeneration == generation else { return }
                stateStore.recordPlaybackError(error)
                stopAutoplayWithError(stateStore.playbackErrorMessage ?? "无法自动播放：播放任务异常。")
            }
        }
    }

    func stopAutoplayTask() {
        let transition = transportReducer.transition(from: transportState, at: .stop)
        transportState = transition.state
        cancelAutoplayTask()
        executeResetIfNeeded(transition)
    }

    func seekAutoplay(toStepIndex stepIndex: Int) {
        restartAutoplay(atStepIndex: stepIndex, reason: .seek)
    }

    func loopAutoplay(toStepIndex stepIndex: Int) {
        restartAutoplay(atStepIndex: stepIndex, reason: .loop)
    }

    private func cancelAutoplayTask() {
        autoplayTask?.cancel()
        autoplayTask = nil
        playbackPositionSeconds = 0
        playbackPositionCapturedAt = nil
        autoplayTimeSchedule = nil
        autoplayContactTimeline = nil
        autoplayGuideSnapshot = nil
        isAutoplayPaused = false
        onPianoDemonstrationContactTimelineChange?(nil, nil)

        stateStore.notationPositionTick = nil
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
        guard stateStore.performancePlan != nil else {
            return "无法自动播放：缺少演奏计划。请重新导入这份 MusicXML。"
        }
        guard stateStore.highlightGuides.isEmpty == false else {
            return "无法自动播放：缺少键盘高亮引导数据。请重新导入这份 MusicXML。"
        }
        guard stateStore.strictTriggerGuideIndex(forStepIndex: stateStore.currentStepIndex) != nil else {
            return "无法自动播放：引导数据不一致（找不到当前步骤的触发点）。请重新导入这份 MusicXML。"
        }
        return nil
    }

    private func sustainPedalIsDown(atTick tick: Int) -> Bool {
        stateStore.performancePlan?.controllerEvents.last {
            $0.controllerNumber == 64 && $0.tick <= tick
        }.map { $0.value >= 64 } ?? false
    }

    private func activeEventIDs(at tick: Int) -> Set<ScorePerformanceNoteEventID> {
        let handMode = stateStore.activeRoundConfiguration?.handMode ?? .both
        guard let performancePlan = stateStore.performancePlan else { return [] }
        return Set(performancePlan.noteEvents.lazy.filter {
            handMode.allows(hand: $0.handAssignment.hand)
                && $0.performedOnTick <= tick
                && $0.performedOffTick > tick
        }.map(\.id))
    }

    private func restartAutoplay(
        atStepIndex stepIndex: Int,
        reason: PerformanceTransportReducer.ResetReason
    ) {
        guard stateStore.autoplayState == .playing,
              case .guiding = stateStore.state,
              stateStore.steps.indices.contains(stepIndex),
              stateStore.activeRange?.contains(stepIndex: stepIndex) ?? true
        else {
            return
        }

        let tick = stateStore.steps[stepIndex].tick
        let boundary: PerformanceTransportReducer.Boundary
        switch reason {
        case .seek:
            boundary = .seek(tick: tick, activeEventIDs: activeEventIDs(at: tick))
        case .loop:
            boundary = .loop(tick: tick, activeEventIDs: activeEventIDs(at: tick))
        case .end, .stop:
            return
        }
        let transition = transportReducer.transition(from: transportState, at: boundary)
        transportState = transition.state
        cancelAutoplayTask()

        executeResetIfNeeded(transition)

        chordAttemptAccumulator.reset()
        stateStore.currentStepIndex = stepIndex
        stateStore.currentHighlightGuideIndex = stateStore.strictTriggerGuideIndex(forStepIndex: stepIndex)
        stateStore.isSustainPedalDown = sustainPedalIsDown(atTick: tick)
        effectHandler?.handle(effect: .refreshAudioRecognition)
        startAutoplayTaskIfNeeded(resetBeforeLoad: requiresResetBeforeLoad)
    }

    @discardableResult
    private func executeResetIfNeeded(_ transition: PerformanceTransportReducer.Transition) -> Bool {
        transition.recordResetDiagnostics(using: diagnosticsReporter, stage: "autoplay.reset")
        guard let resetCommands = transition.commands.compactMap({ command -> [PerformanceTransportCommand]? in
            if case let .reset(_, transportCommands, _, _) = command { return transportCommands }
            return nil
        }).first else { return false }
        let previousResetTask = pendingResetTask
        let sequencerPlaybackService = sequencerPlaybackService
        pendingResetTask = Task {
            await previousResetTask?.value
            await sequencerPlaybackService.stop(resetCommands: resetCommands)
        }
        requiresResetBeforeLoad = false
        return true
    }

    private func stopAutoplayWithError(_ message: String) {
        stateStore.autoplayState = .off
        stopAutoplayTask()
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
        plan: ScorePerformancePlan,
        timeline: AutoplayPerformanceTimeline,
        guides: [PianoHighlightGuide],
        steps: [PracticeStep],
        tempoMap: MusicXMLTempoMap,
        timingBaseTick: Int,
        resetBeforeLoad: Bool
    ) async throws {
        let initialSustainPedalDown = sustainPedalIsDown(atTick: timingBaseTick)
        stateStore.isSustainPedalDown = initialSustainPedalDown

        do {
            await pendingResetTask?.value
            try await sequencerPlaybackService.warmUp()
        } catch {
            guard Task.isCancelled == false, autoplayTaskGeneration == generation else { return }
            stateStore.recordPlaybackError(error)
            stopAutoplayWithError(stateStore.playbackErrorMessage ?? "无法自动播放：音频服务初始化失败。")
            return
        }

        guard Task.isCancelled == false, autoplayTaskGeneration == generation else { return }

        if resetBeforeLoad {
            await sequencerPlaybackService.stop(
                resetCommands: PerformanceTransportReducer.fullResetCommands
            )
            requiresResetBeforeLoad = false
        }

        let sequence: PracticeSequencerSequence
        do {
            sequence = try await playbackSequenceBuilder.buildPerformanceSequence(
                timeline: timeline,
                tempoMap: tempoMap,
                startTick: timingBaseTick,
                endTick: nil,
                leadInSeconds: leadInSeconds
            )
        } catch {
            guard Task.isCancelled == false, autoplayTaskGeneration == generation else { return }
            stateStore.recordPlaybackError(error)
            stopAutoplayWithError(stateStore.playbackErrorMessage ?? "无法自动播放：构建 MIDI 序列失败。")
            return
        }

        guard Task.isCancelled == false, autoplayTaskGeneration == generation else { return }

        let timeSchedule = AutoplayTimelineTimeSchedule(
            timeline: timeline,
            tickToSeconds: { tempoMap.timeSeconds(atTick: $0) },
            startTick: timingBaseTick,
            leadInSeconds: leadInSeconds
        )
        let contactTimeline = PianoKeyContactTimeline(
            plan: plan,
            timeline: timeline,
            schedule: timeSchedule,
            guideProjection: guides,
            stepProjection: steps
        )

        do {
            try await sequencerPlaybackService.load(sequence: sequence)
            guard Task.isCancelled == false, autoplayTaskGeneration == generation else { return }
            try await sequencerPlaybackService.setPlaybackRate(autoplayPlaybackRate)
            guard Task.isCancelled == false, autoplayTaskGeneration == generation else { return }
            try await sequencerPlaybackService.play(fromSeconds: 0)
            guard Task.isCancelled == false, autoplayTaskGeneration == generation else { return }
            requiresResetBeforeLoad = true
            autoplayTimeSchedule = timeSchedule
            autoplayContactTimeline = contactTimeline
            autoplayGuideSnapshot = guides
            onPianoDemonstrationContactTimelineChange?(generation, contactTimeline)
            recordPlaybackPosition(0)
        } catch {
            guard Task.isCancelled == false, autoplayTaskGeneration == generation else { return }
            stateStore.recordPlaybackError(error)
            stopAutoplayWithError(stateStore.playbackErrorMessage ?? "无法自动播放：播放服务启动失败。")
            return
        }

        guard Task.isCancelled == false, autoplayTaskGeneration == generation else { return }

        var cursor = AutoplayTimelineTimeCursor(schedule: timeSchedule)

        var pedalCursor = AutoplayTimelinePedalTimeCursor(
            timeline: timeline,
            timeSchedule: timeSchedule,
            initialIsDown: stateStore.isSustainPedalDown
        )

        let sequenceEndSeconds = max(0, sequence.durationSeconds)

        while Task.isCancelled == false, autoplayTaskGeneration == generation {
            guard stateStore.autoplayState == .playing else { break }
            guard case .guiding = stateStore.state else { break }

            if isAutoplayPaused {
                try? await sleeper.sleep(for: .milliseconds(33))
                continue
            }

            let nowSeconds = await sequencerPlaybackService.currentSeconds()
            guard Task.isCancelled == false, autoplayTaskGeneration == generation else { return }
            if isAutoplayPaused { continue }
            recordPlaybackPosition(nowSeconds)

            if let isDown = pedalCursor.advance(toSeconds: nowSeconds) {
                stateStore.isSustainPedalDown = isDown
            }

            let cursorEvents = cursor.advance(toSeconds: nowSeconds)
            for scheduled in cursorEvents {
                switch scheduled.event {
                case let .step(index):
                    advanceAutoplayStep(to: index)
                case let .guide(index, _):
                    stateStore.currentHighlightGuideIndex = index
                case .position:
                    break
                }
            }

            if let final = cursorEvents.last { stateStore.notationPositionTick = final.tick }

            if nowSeconds >= sequenceEndSeconds, pedalCursor.isFinished, cursor.isFinished {
                break
            }

            try? await sleeper.sleep(for: .milliseconds(33))
        }

        if Task.isCancelled == false, autoplayTaskGeneration == generation {
            let transition = transportReducer.transition(from: transportState, at: .end)
            transportState = transition.state
            executeResetIfNeeded(transition)
            autoplayTask = nil
            playbackPositionCapturedAt = nil
            autoplayTimeSchedule = nil
            autoplayContactTimeline = nil
            autoplayGuideSnapshot = nil
            onPianoDemonstrationContactTimelineChange?(nil, nil)
        }
    }

    private func recordPlaybackPosition(_ seconds: TimeInterval) {
        guard seconds.isFinite else { return }
        playbackPositionSeconds = max(0, seconds)
        playbackPositionCapturedAt = performanceClock.now()
    }

    private func advanceAutoplayStep(to stepIndex: Int) {
        guard stateStore.steps.indices.contains(stepIndex) else { return }
        guard stateStore.currentStepIndex != stepIndex else { return }
        chordAttemptAccumulator.reset()
        stateStore.currentStepIndex = stepIndex
        effectHandler?.handle(effect: .refreshAudioRecognition)
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
        timeSchedule: AutoplayTimelineTimeSchedule,
        initialIsDown: Bool
    ) {
        var scheduled: [TimedPedal] = []
        scheduled.reserveCapacity(32)

        for event in timeline.events {
            guard case let .controlChange(controller, value) = event.kind,
                  controller == 64,
                  let timeSeconds = timeSchedule.timeSeconds(forEventID: event.id)
            else {
                continue
            }
            scheduled.append(TimedPedal(
                timeSeconds: timeSeconds,
                isDown: value >= 64
            ))
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
