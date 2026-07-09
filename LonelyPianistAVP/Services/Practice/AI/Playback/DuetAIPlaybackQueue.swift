import Foundation
import os

actor DuetAIPlaybackQueue {
    struct SubmitResult: Equatable, Sendable {
        let shiftedSchedule: [PracticeSequencerMIDIEvent]
        let baseDelaySeconds: TimeInterval
        let replacedPendingWindow: Bool
        let windowEndUptimeSeconds: TimeInterval
    }

    private struct WindowItem: Sendable {
        let schedule: [PracticeSequencerMIDIEvent]
        let routing: PracticeSoundRoutingSettings
        let startUptimeSeconds: TimeInterval
        let endUptimeSeconds: TimeInterval
    }

    private let logger: Logger
    private let nowUptimeSeconds: @Sendable () -> TimeInterval
    private let sleepFor: @Sendable (Duration) async -> Void
    private let buildSequence: @Sendable ([PracticeSequencerMIDIEvent]) async throws -> PracticeSequencerSequence
    private let playbackServiceFactory: @MainActor () -> DuetAIPlaybackServiceFactory
    private let onPlaybackActiveChanged: @Sendable @MainActor (Bool) -> Void

    private var pendingWindow: WindowItem?
    private var playbackLoopTask: Task<Void, Never>?
    private var currentSegmentEndUptimeSeconds: TimeInterval = 0

    init(
        logger: Logger,
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
        self.logger = logger
        self.nowUptimeSeconds = nowUptimeSeconds
        self.sleepFor = sleepFor
        self.buildSequence = buildSequence
        self.playbackServiceFactory = playbackServiceFactory
        self.onPlaybackActiveChanged = onPlaybackActiveChanged
    }

    func stopAll() async {
        playbackLoopTask?.cancel()
        playbackLoopTask = nil
        pendingWindow = nil
        currentSegmentEndUptimeSeconds = 0

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
        let (shiftedSchedule, baseDelaySeconds, startUptimeSeconds, endUptimeSeconds) = computeShiftedSchedule(
            schedule: schedule,
            nowUptimeSeconds: now
        )

        pendingWindow = WindowItem(
            schedule: shiftedSchedule,
            routing: routing,
            startUptimeSeconds: startUptimeSeconds,
            endUptimeSeconds: endUptimeSeconds
        )
        currentSegmentEndUptimeSeconds = max(currentSegmentEndUptimeSeconds, endUptimeSeconds)
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
        playbackLoopTask = Task { [weak self] in
            guard let self else { return }
            await self.playbackLoop()
        }
    }

    private func playbackLoop() async {
        defer {
            playbackLoopTask = nil
            currentSegmentEndUptimeSeconds = 0
            Task { @MainActor [onPlaybackActiveChanged] in
                onPlaybackActiveChanged(false)
            }
        }

        while Task.isCancelled == false {
            guard let item = pendingWindow else { break }
            pendingWindow = nil
            currentSegmentEndUptimeSeconds = item.endUptimeSeconds

            await MainActor.run {
                onPlaybackActiveChanged(true)
            }
            await play(item)
        }
    }

    private func play(_ item: WindowItem) async {
        let sequence: PracticeSequencerSequence
        do {
            sequence = try await buildSequence(item.schedule)
        } catch {
            logger.warning("continuous duet buildSequence failed: \(String(describing: error), privacy: .public)")
            return
        }

        let playbackTask = Task { @MainActor [logger, playbackServiceFactory, sleepFor] in
            let service = playbackServiceFactory().playbackService(for: item.routing)
            do {
                try service.warmUp()
                try service.load(sequence: sequence)
                try service.play(fromSeconds: 0)
            } catch {
                logger.warning("continuous duet playback start failed: \(String(describing: error), privacy: .public)")
                return
            }

            let endSeconds = max(0, sequence.durationSeconds)
            while Task.isCancelled == false {
                if service.currentSeconds() >= endSeconds { break }
                await sleepFor(.milliseconds(16))
            }
            service.stop()
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
    ) -> (shifted: [PracticeSequencerMIDIEvent], baseDelaySeconds: TimeInterval, startUptimeSeconds: TimeInterval, endUptimeSeconds: TimeInterval) {
        guard schedule.isEmpty == false else {
            return ([], 0, nowUptimeSeconds, nowUptimeSeconds)
        }

        let firstEventSeconds = schedule.map(\.timeSeconds).min() ?? 0
        let lastEventSeconds = schedule.map(\.timeSeconds).max() ?? 0
        let leadInSeconds: TimeInterval = 0.05
        let desiredStartUptimeSeconds = max(nowUptimeSeconds + leadInSeconds, currentSegmentEndUptimeSeconds)
        let desiredOffsetSeconds = desiredStartUptimeSeconds - nowUptimeSeconds
        let delta = max(0, desiredOffsetSeconds - firstEventSeconds)

        let shifted = schedule.map { event in
            PracticeSequencerMIDIEvent(
                timeSeconds: max(0, event.timeSeconds + delta),
                kind: event.kind
            )
        }
        return (
            shifted,
            delta,
            desiredStartUptimeSeconds,
            nowUptimeSeconds + lastEventSeconds + delta
        )
    }
}
