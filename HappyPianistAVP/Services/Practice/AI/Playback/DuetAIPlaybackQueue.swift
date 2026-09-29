import Foundation
import Diagnostics
import Practice

actor DuetAIPlaybackQueue {
    enum PlaybackPhase: Equatable, Sendable {
        case idle
        case preparing
        case playing
    }

    struct SubmitResult: Equatable {
        let shiftedSchedule: [PracticeSequencerMIDIEvent]
        let baseDelaySeconds: TimeInterval
        let replacedPendingWindow: Bool
        let windowEndUptimeSeconds: TimeInterval
        let wasAccepted: Bool
    }

    private struct WindowItem {
        let schedule: [PracticeSequencerMIDIEvent]
        let routing: PracticeSoundRoutingSettings
        let provider: ImprovBackendKind?
        let requestGeneration: Int
    }

    private let diagnosticsReporter: (any DiagnosticsReporting)?
    private let nowUptimeSeconds: @Sendable () -> TimeInterval
    private let sleepFor: @Sendable (Duration) async -> Void
    private let buildSequence: @Sendable ([PracticeSequencerMIDIEvent]) async throws -> PracticeSequencerSequence
    private let playbackServiceFactory: @MainActor () -> DuetAIPlaybackServiceFactory
    private let onPlaybackPhaseChanged: @Sendable @MainActor (PlaybackPhase) -> Void

    private var pendingWindow: WindowItem?
    private var playbackLoopTask: Task<Void, Never>?
    /// Invalidates the entire playback lifecycle. Only teardown paths increment this value.
    private var playbackGeneration = 0
    /// Invalidates work that has not crossed the successful `service.play()` boundary yet.
    private var preparationEpoch = 0
    /// Rejects stale generated windows. It must never terminate a window that is already playing.
    private var minimumRequestGeneration = 0
    /// Generation currently between dequeue and the successful `service.play()` boundary.
    private var preparingRequestGeneration: Int?
    private var playbackPhase: PlaybackPhase = .idle

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
        onPlaybackPhaseChanged: @escaping @Sendable @MainActor (PlaybackPhase) -> Void
    ) {
        self.diagnosticsReporter = diagnosticsReporter
        self.nowUptimeSeconds = nowUptimeSeconds
        self.sleepFor = sleepFor
        self.buildSequence = buildSequence
        self.playbackServiceFactory = playbackServiceFactory
        self.onPlaybackPhaseChanged = onPlaybackPhaseChanged
    }

    func stopAll() async {
        await cancelAll(rejectingThrough: nil)
    }

    func stopAll(rejectingThrough requestGeneration: Int) async {
        guard requestGeneration >= minimumRequestGeneration else { return }
        await cancelAll(rejectingThrough: requestGeneration)
    }

    /// Drops pending and currently-preparing work older than the new user-input generation.
    /// Already-playing audio intentionally survives until a Companion decision explicitly yields it.
    func invalidateUnstartedWindows(through requestGeneration: Int) {
        guard requestGeneration > minimumRequestGeneration else { return }
        let shouldInvalidatePreparation = preparingRequestGeneration.map {
            $0 < requestGeneration
        } ?? false
        minimumRequestGeneration = requestGeneration
        if shouldInvalidatePreparation {
            preparationEpoch &+= 1
            preparingRequestGeneration = nil
        }
        if pendingWindow?.requestGeneration ?? .max < minimumRequestGeneration {
            pendingWindow = nil
        }
    }

    /// Clears future work without stopping the current playing window.
    func clearUnstartedWindows() {
        preparationEpoch &+= 1
        preparingRequestGeneration = nil
        pendingWindow = nil
    }

    /// Companion `.yield`: stop current playback and remove every unstarted window.
    func stopCurrentPlaybackAndClearPending() async {
        await cancelAll(rejectingThrough: nil)
    }

    private func cancelAll(rejectingThrough requestGeneration: Int?) async {
        if let requestGeneration {
            minimumRequestGeneration = max(minimumRequestGeneration, requestGeneration)
        }
        playbackGeneration &+= 1
        preparationEpoch &+= 1
        playbackLoopTask?.cancel()
        playbackLoopTask = nil
        preparingRequestGeneration = nil
        pendingWindow = nil

        let serviceFactory = await MainActor.run { playbackServiceFactory() }
        await serviceFactory.stopAll()
        await transition(to: .idle)
    }

    func submitWindow(
        schedule: [PracticeSequencerMIDIEvent],
        routing: PracticeSoundRoutingSettings,
        submittedAtUptimeSeconds: TimeInterval? = nil,
        provider: ImprovBackendKind? = nil,
        requestGeneration: Int = .max
    ) async -> SubmitResult {
        let now = submittedAtUptimeSeconds ?? nowUptimeSeconds()
        guard requestGeneration >= minimumRequestGeneration else {
            return SubmitResult(
                shiftedSchedule: [],
                baseDelaySeconds: 0,
                replacedPendingWindow: false,
                windowEndUptimeSeconds: now,
                wasAccepted: false
            )
        }
        let replacedPendingWindow = pendingWindow != nil
        let (shiftedSchedule, baseDelaySeconds, endUptimeSeconds) = computeShiftedSchedule(
            schedule: schedule,
            nowUptimeSeconds: now
        )

        pendingWindow = WindowItem(
            schedule: shiftedSchedule,
            routing: routing,
            provider: provider,
            requestGeneration: requestGeneration
        )
        ensurePlaybackLoop()

        return SubmitResult(
            shiftedSchedule: shiftedSchedule,
            baseDelaySeconds: baseDelaySeconds,
            replacedPendingWindow: replacedPendingWindow,
            windowEndUptimeSeconds: endUptimeSeconds,
            wasAccepted: true
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
        while Task.isCancelled == false, generation == playbackGeneration {
            guard let item = pendingWindow else { break }
            pendingWindow = nil
            guard item.requestGeneration >= minimumRequestGeneration else { continue }

            let epoch = preparationEpoch
            preparingRequestGeneration = item.requestGeneration
            await transition(to: .preparing)
            await play(item, playbackGeneration: generation, preparationEpoch: epoch)
            if preparingRequestGeneration == item.requestGeneration {
                preparingRequestGeneration = nil
            }
            if generation == playbackGeneration, playbackPhase == .preparing {
                await transition(to: .idle)
            }
        }

        if generation == playbackGeneration {
            playbackLoopTask = nil
            if playbackPhase != .idle {
                await transition(to: .idle)
            }
        }
    }

    private func play(
        _ item: WindowItem,
        playbackGeneration generation: Int,
        preparationEpoch epoch: Int
    ) async {
        guard isUnstartedCurrent(
            playbackGeneration: generation,
            preparationEpoch: epoch,
            requestGeneration: item.requestGeneration
        ) else { return }

        let sequence: PracticeSequencerSequence
        do {
            sequence = try await buildSequence(item.schedule)
        } catch {
            guard isUnstartedCurrent(
                playbackGeneration: generation,
                preparationEpoch: epoch,
                requestGeneration: item.requestGeneration
            ) else { return }
            diagnosticsReporter?.recordSystem(
                severity: .warning,
                category: .ai,
                stage: "continuousDuet.buildSequence",
                summary: "AI 即兴序列构建失败",
                reason: "provider=\(item.provider?.rawValue ?? "unknown");failure=sequence_build"
            )
            return
        }

        guard isUnstartedCurrent(
            playbackGeneration: generation,
            preparationEpoch: epoch,
            requestGeneration: item.requestGeneration
        ) else { return }

        let playbackTask = Task { @MainActor [weak self, diagnosticsReporter, playbackServiceFactory, sleepFor] in
            guard let self,
                  Task.isCancelled == false,
                  await self.isUnstartedCurrent(
                      playbackGeneration: generation,
                      preparationEpoch: epoch,
                      requestGeneration: item.requestGeneration
                  )
            else { return }

            let service = playbackServiceFactory().playbackService(for: item.routing)
            do {
                try await service.warmUp()
                guard Task.isCancelled == false,
                      await self.isUnstartedCurrent(
                          playbackGeneration: generation,
                          preparationEpoch: epoch,
                          requestGeneration: item.requestGeneration
                      )
                else { return }

                await service.stop(resetCommands: PerformanceTransportReducer.fullResetCommands)
                guard Task.isCancelled == false,
                      await self.isUnstartedCurrent(
                          playbackGeneration: generation,
                          preparationEpoch: epoch,
                          requestGeneration: item.requestGeneration
                      )
                else { return }

                try await service.load(sequence: sequence)
                guard Task.isCancelled == false,
                      await self.isUnstartedCurrent(
                          playbackGeneration: generation,
                          preparationEpoch: epoch,
                          requestGeneration: item.requestGeneration
                      )
                else { return }

                try await service.play(fromSeconds: 0)
                guard await self.markPlayingIfUnstartedCurrent(
                    playbackGeneration: generation,
                    preparationEpoch: epoch,
                    requestGeneration: item.requestGeneration
                ) else {
                    await service.stop(resetCommands: PerformanceTransportReducer.fullResetCommands)
                    return
                }
            } catch {
                guard await self.isUnstartedCurrent(
                    playbackGeneration: generation,
                    preparationEpoch: epoch,
                    requestGeneration: item.requestGeneration
                ) else { return }
                diagnosticsReporter?.recordSystem(
                    severity: .warning,
                    category: .ai,
                    stage: "continuousDuet.playbackStart",
                    summary: "AI 即兴播放启动失败",
                    reason: "provider=\(item.provider?.rawValue ?? "unknown");failure=playback_start"
                )
                return
            }

            let endSeconds = max(0, sequence.durationSeconds)
            while Task.isCancelled == false {
                guard await self.isPlaybackLifecycleCurrent(generation) else { return }
                if await service.currentSeconds() >= endSeconds { break }
                await sleepFor(.milliseconds(16))
                await Task.yield()
            }
            guard await self.isPlaybackLifecycleCurrent(generation) else { return }
            await service.stop(resetCommands: PerformanceTransportReducer.fullResetCommands)
            await self.finishPlayingIfLifecycleIsCurrent(playbackGeneration: generation)
        }

        await withTaskCancellationHandler {
            _ = await playbackTask.result
        } onCancel: {
            playbackTask.cancel()
        }
    }

    private func isUnstartedCurrent(
        playbackGeneration: Int,
        preparationEpoch: Int,
        requestGeneration: Int
    ) -> Bool {
        playbackGeneration == self.playbackGeneration
            && preparationEpoch == self.preparationEpoch
            && requestGeneration >= minimumRequestGeneration
    }

    private func isPlaybackLifecycleCurrent(_ generation: Int) -> Bool {
        generation == playbackGeneration
    }

    private func markPlayingIfUnstartedCurrent(
        playbackGeneration generation: Int,
        preparationEpoch epoch: Int,
        requestGeneration: Int
    ) async -> Bool {
        guard isUnstartedCurrent(
            playbackGeneration: generation,
            preparationEpoch: epoch,
            requestGeneration: requestGeneration
        ) else { return false }
        if preparingRequestGeneration == requestGeneration {
            preparingRequestGeneration = nil
        }
        await transition(to: .playing)
        return true
    }

    private func finishPlayingIfLifecycleIsCurrent(playbackGeneration generation: Int) async {
        guard generation == playbackGeneration else { return }
        await transition(to: .idle)
    }

    private func transition(to nextPhase: PlaybackPhase) async {
        guard playbackPhase != nextPhase else { return }
        playbackPhase = nextPhase
        await MainActor.run {
            onPlaybackPhaseChanged(nextPhase)
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
