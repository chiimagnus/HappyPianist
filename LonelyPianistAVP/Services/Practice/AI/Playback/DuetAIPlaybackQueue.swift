import Foundation
import os

actor DuetAIPlaybackQueue {
    struct EnqueueResult: Equatable, Sendable {
        let shiftedSchedule: [PracticeSequencerMIDIEvent]
        let baseDelaySeconds: TimeInterval
    }

    private struct QueueItem: Sendable {
        let schedule: [PracticeSequencerMIDIEvent]
        let routing: PracticeSoundRoutingSettings
        let enqueuedAtUptimeSeconds: TimeInterval
    }

    private let logger: Logger
    private let nowUptimeSeconds: @Sendable () -> TimeInterval
    private let sleepFor: @Sendable (Duration) async -> Void
    private let buildSequence: @Sendable ([PracticeSequencerMIDIEvent]) async throws -> PracticeSequencerSequence
    private let playbackServiceFactory: @MainActor () -> DuetAIPlaybackServiceFactory
    private let onPlaybackActiveChanged: @Sendable @MainActor (Bool) -> Void

    private var aiEndUptimeSeconds: TimeInterval = 0
    private var queue: [QueueItem] = []
    private var playbackLoopTask: Task<Void, Never>?

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
        queue.removeAll(keepingCapacity: true)
        aiEndUptimeSeconds = 0

        await MainActor.run {
            playbackServiceFactory().stopAll()
            onPlaybackActiveChanged(false)
        }
    }

    func enqueue(
        schedule: [PracticeSequencerMIDIEvent],
        routing: PracticeSoundRoutingSettings,
        enqueuedAtUptimeSeconds: TimeInterval? = nil
    ) async -> EnqueueResult {
        let now = enqueuedAtUptimeSeconds ?? nowUptimeSeconds()
        let (shifted, baseDelay) = computeShiftedSchedule(schedule: schedule, nowUptimeSeconds: now)

        updateAIEndUptimeIfNeeded(shiftedSchedule: shifted, nowUptimeSeconds: now)

        queue.append(QueueItem(schedule: shifted, routing: routing, enqueuedAtUptimeSeconds: now))
        ensurePlaybackLoop()

        return EnqueueResult(shiftedSchedule: shifted, baseDelaySeconds: baseDelay)
    }

    private func ensurePlaybackLoop() {
        guard playbackLoopTask == nil else { return }

        playbackLoopTask = Task { [weak self] in
            guard let self else { return }
            await self.playbackLoop()
        }
    }

    private func playbackLoop() async {
        await MainActor.run {
            onPlaybackActiveChanged(true)
        }
        defer {
            Task { @MainActor [onPlaybackActiveChanged] in
                onPlaybackActiveChanged(false)
            }
        }

        while Task.isCancelled == false {
            guard queue.isEmpty == false else { break }
            let item = queue.removeFirst()
            await playOne(item)
        }

        playbackLoopTask = nil
    }

    private func playOne(_ item: QueueItem) async {
        let sequence: PracticeSequencerSequence
        do {
            sequence = try await buildSequence(item.schedule)
        } catch {
            logger.warning("ai playback buildSequence failed: \(String(describing: error), privacy: .public)")
            return
        }

        let playbackTask = Task { @MainActor [logger, playbackServiceFactory, sleepFor] in
            let service = playbackServiceFactory().playbackService(for: item.routing)

            do {
                try service.warmUp()
            } catch {
                logger.warning("ai playback warmUp failed: \(String(describing: error), privacy: .public)")
                return
            }

            do {
                try service.load(sequence: sequence)
                try service.play(fromSeconds: 0)
            } catch {
                logger.warning("ai playback start failed: \(String(describing: error), privacy: .public)")
                return
            }

            let endSeconds = max(0, sequence.durationSeconds)
            while Task.isCancelled == false {
                let nowSeconds = service.currentSeconds()
                if nowSeconds >= endSeconds { break }
                await sleepFor(.milliseconds(33))
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
    ) -> (shifted: [PracticeSequencerMIDIEvent], baseDelaySeconds: TimeInterval) {
        guard schedule.isEmpty == false else { return ([], 0) }

        let minNoteOnSeconds = schedule.compactMap { event -> TimeInterval? in
            if case .noteOn = event.kind { return event.timeSeconds }
            return nil
        }.min() ?? schedule.map(\.timeSeconds).min() ?? 0

        let leadInSeconds: TimeInterval = 0.05
        let desiredFirstNoteOnUptime = max(nowUptimeSeconds + leadInSeconds, aiEndUptimeSeconds)
        let desiredFirstNoteOnFromNow = desiredFirstNoteOnUptime - nowUptimeSeconds
        let delta = max(0, desiredFirstNoteOnFromNow - minNoteOnSeconds)

        if abs(delta) < 1e-9 {
            return (schedule, 0)
        }

        let shifted = schedule.map { event in
            PracticeSequencerMIDIEvent(timeSeconds: max(0, event.timeSeconds + delta), kind: event.kind)
        }

        return (shifted, delta)
    }

    private func updateAIEndUptimeIfNeeded(shiftedSchedule: [PracticeSequencerMIDIEvent], nowUptimeSeconds: TimeInterval) {
        let lastNoteOnSeconds = shiftedSchedule.compactMap { event -> TimeInterval? in
            if case .noteOn = event.kind { return event.timeSeconds }
            return nil
        }.max()

        guard let lastNoteOnSeconds else { return }
        aiEndUptimeSeconds = max(aiEndUptimeSeconds, nowUptimeSeconds + lastNoteOnSeconds)
    }
}
