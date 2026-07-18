import Foundation

actor DuetAIPlaybackQueue {
    struct SubmitResult: Equatable {
        let shiftedSchedule: [PracticeSequencerMIDIEvent]
        let baseDelaySeconds: TimeInterval
        let replacedPendingWindow: Bool
        let windowEndUptimeSeconds: TimeInterval
    }

    private struct WindowItem {
        let schedule: [PracticeSequencerMIDIEvent]
        let routing: PracticeSoundRoutingSettings
    }

    private let diagnosticsReporter: (any DiagnosticsReporting)?
    private let nowUptimeSeconds: @Sendable () -> TimeInterval
    private let sleepFor: @Sendable (Duration) async -> Void
    private let buildSequence: @Sendable ([PracticeSequencerMIDIEvent]) async throws -> PracticeSequencerSequence
    private let playbackServiceFactory: @MainActor () -> DuetAIPlaybackServiceFactory
    private let onPlaybackActiveChanged: @Sendable @MainActor (Bool) -> Void

    private var pendingWindow: WindowItem?
    private var playbackLoopTask: Task<Void, Never>?
    private var playbackGeneration = 0

    init(
        diagnosticsReporter: (any DiagnosticsReporting)? = nil,
        nowUptimeSeconds: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        sleepFor: @escaping @Sendable (Duration) async -> Void = { duration in try? await Task.sleep(for: duration) },
        buildSequence: @escaping @Sendable ([PracticeSequencerMIDIEvent]) async throws -> PracticeSequencerSequence = { schedule in
            try await Task.detached(priority: .userInitiated) {
                try PracticeSequencerSequenceBuilder().buildSequence(from: schedule)
            }.value
        },
        playbackServiceFactory: @escaping @MainActor () -> DuetAIPlaybackServiceFactory,
        onPlaybackActiveChanged: @escaping @Sendable @MainActor (Bool) -> Void
    ) {
        self.diagnosticsReporter = diagnosticsReporter
        self.nowUptimeSeconds = nowUptimeSeconds
        self.sleepFor = sleepFor
        self.buildSequence = buildSequence
        self.playbackServiceFactory = playbackServiceFactory
        self.onPlaybackActiveChanged = onPlaybackActiveChanged
    }

    func stopAll() async {
        playbackGeneration &+= 1
        playbackLoopTask?.cancel()
        playbackLoopTask = nil
        pendingWindow = nil

        await MainActor.run {
            playbackServiceFactory().stopAll()
            onPlaybackActiveChanged(false)
        }
    }

    func clearPendingWindow() {
        pendingWindow = nil
    }

    func submitWindow(
        schedule: [PracticeSequencerMIDIEvent],
        routing: PracticeSoundRoutingSettings,
        submittedAtUptimeSeconds: TimeInterval? = nil
    ) async -> SubmitResult {
        let now = submittedAtUptimeSeconds ?? nowUptimeSeconds()
        let replacedPendingWindow = pendingWindow != nil
        let (shiftedSchedule, baseDelaySeconds, endUptimeSeconds) = computeShiftedSchedule(
            schedule: schedule,
            nowUptimeSeconds: now
        )

        pendingWindow = WindowItem(
            schedule: shiftedSchedule,
            routing: routing
        )
        ensurePlaybackLoop()

        return SubmitResult(
            shiftedSchedule: shiftedSchedule,
            baseDelaySeconds: baseDelaySeconds,
            replacedPendingWindow: replacedPendingWindow,
            windowEndUptimeSeconds: endUptimeSeconds
        )
    }

    private func ensurePlaybackLoop() {
        guard playbackLoopTask == nil else { return }
        let generation = playbackGeneration
        playbackLoopTask = Task { [weak self] in
            guard let self else { return }
            await self.playbackLoop(generation: generation)
        }
    }

    private func playbackLoop(generation: Int) async {
        defer {
            if generation == playbackGeneration {
                playbackLoopTask = nil
                Task { @MainActor [onPlaybackActiveChanged] in
                    onPlaybackActiveChanged(false)
                }
            }
        }

        while Task.isCancelled == false, generation == playbackGeneration {
            guard let item = pendingWindow else { break }
            pendingWindow = nil

            await MainActor.run {
                onPlaybackActiveChanged(true)
            }
            guard Task.isCancelled == false, generation == playbackGeneration else { break }
            await play(item, generation: generation)
        }
    }

    private func play(_ item: WindowItem, generation: Int) async {
        let sequence: PracticeSequencerSequence
        do {
            sequence = try await buildSequence(item.schedule)
        } catch {
            diagnosticsReporter?.recordSystem(
                severity: .warning,
                category: .ai,
                stage: "continuousDuet.buildSequence",
                summary: "AI 即兴序列构建失败",
                reason: String(describing: error)
            )
            return
        }

        guard Task.isCancelled == false, generation == playbackGeneration else { return }

        let playbackTask = Task { @MainActor [diagnosticsReporter, playbackServiceFactory, sleepFor] in
            guard Task.isCancelled == false else { return }
            let service = playbackServiceFactory().playbackService(for: item.routing)
            do {
                try service.warmUp()
                service.stop(resetCommands: PerformanceTransportReducer.fullResetCommands)
                try service.load(sequence: sequence)
                try service.play(fromSeconds: 0)
            } catch {
                diagnosticsReporter?.recordSystem(
                    severity: .warning,
                    category: .ai,
                    stage: "continuousDuet.playbackStart",
                    summary: "AI 即兴播放启动失败",
                    reason: String(describing: error)
                )
                return
            }

            let endSeconds = max(0, sequence.durationSeconds)
            while Task.isCancelled == false {
                if service.currentSeconds() >= endSeconds { break }
                await sleepFor(.milliseconds(16))
                await Task.yield()
            }
            service.stop(resetCommands: PerformanceTransportReducer.fullResetCommands)
        }

        await withTaskCancellationHandler {
            _ = await playbackTask.result
        } onCancel: {
            playbackTask.cancel()
        }
    }

    private func computeShiftedSchedule(
        schedule: [PracticeSequencerMIDIEvent],
        nowUptimeSeconds: TimeInterval
    ) -> (shifted: [PracticeSequencerMIDIEvent], baseDelaySeconds: TimeInterval, endUptimeSeconds: TimeInterval) {
        guard schedule.isEmpty == false else {
            return ([], 0, nowUptimeSeconds)
        }

        let firstEventSeconds = schedule.map(\.timeSeconds).min() ?? 0
        let lastEventSeconds = schedule.map(\.timeSeconds).max() ?? 0
        let leadInSeconds: TimeInterval = 0.05
        // The playback loop already serializes windows. Only add a sequence-relative lead-in;
        // carrying the active segment's wall-clock remainder into this sequence would wait twice.
        let delta = max(0, leadInSeconds - firstEventSeconds)

        let shifted = schedule.map { event in
            PracticeSequencerMIDIEvent(
                timeSeconds: max(0, event.timeSeconds + delta),
                kind: event.kind
            )
        }
        return (
            shifted,
            delta,
            nowUptimeSeconds + lastEventSeconds + delta
        )
    }
}
