import Foundation
@testable import HappyPianistAVP
import os
import Testing

struct CoreMIDIPracticePlaybackServiceStopTests {
    @Test func stopExecutesReducerResetCommandsInOrder() async throws {
        let output = FakeMIDIOutputService()
        let destinationUniqueID: Int32 = 1234
        let plan = makeTestScorePerformancePlan(notes: [
            TestScorePerformanceNote(midiNote: 60, onTick: 0),
        ])
        let eventID = plan.noteEvents[0].id
        let playback = await MainActor.run {
            CoreMIDIPracticePlaybackService(destinationUniqueID: destinationUniqueID, outputService: output, channel: 0)
        }

        try await MainActor.run {
            try playback.load(sequence: PracticeSequencerSequence(
                midiData: Data(),
                durationSeconds: 1,
                events: [PracticeSequencerMIDIEvent(
                    sourceEventID: eventID.description,
                    timeSeconds: 0,
                    kind: .noteOn(midi: 60, velocity: 96)
                )]
            ))
        }
        let callCountBeforeStop = output.callsSnapshot().count
        await MainActor.run {
            playback.stop(resetCommands: PerformanceTransportReducer.resetCommands(eventIDs: [eventID]))
        }

        #expect(Array(output.callsSnapshot().dropFirst(callCountBeforeStop)) == [
            .noteOff(note: 60, channel: 0, destination: destinationUniqueID),
            .controlChange(controller: 64, value: 0, channel: 0, destination: destinationUniqueID),
            .controlChange(controller: 66, value: 0, channel: 0, destination: destinationUniqueID),
            .controlChange(controller: 67, value: 0, channel: 0, destination: destinationUniqueID),
            .controlChange(controller: 123, value: 0, channel: 0, destination: destinationUniqueID),
            .controlChange(controller: 120, value: 0, channel: 0, destination: destinationUniqueID),
        ])
    }

    @Test func stopContinuesResetAfterSendFailureAndReportsAggregate() async {
        let output = FakeMIDIOutputService(failingControllers: [64, 120])
        let diagnostics = InMemoryDiagnosticsReporter()
        let destinationUniqueID: Int32 = 1240
        let playback = await MainActor.run {
            CoreMIDIPracticePlaybackService(
                destinationUniqueID: destinationUniqueID,
                outputService: output,
                diagnosticsReporter: diagnostics,
                channel: 0
            )
        }

        await MainActor.run {
            playback.stop(resetCommands: PerformanceTransportReducer.fullResetCommands)
        }

        let controllers = output.callsSnapshot().compactMap { call -> UInt8? in
            guard case let .controlChange(controller, _, _, _) = call else { return nil }
            return controller
        }
        #expect(controllers == [64, 66, 67, 123, 120])
        let events = await waitForCoreMIDIResetDiagnostic(diagnostics)
        #expect(events.contains { event in
            event.stage == "coreMIDI.transportReset"
                && event.reason == "failureCount=2"
        })
    }

    @Test func playbackSendsCanonicalSequenceEventsIncludingControllers() async throws {
        let output = FakeMIDIOutputService()
        let destinationUniqueID: Int32 = 5678
        let playback = await MainActor.run {
            CoreMIDIPracticePlaybackService(
                destinationUniqueID: destinationUniqueID,
                outputService: output,
                channel: 2
            )
        }
        let sequence = PracticeSequencerSequence(
            midiData: Data(),
            durationSeconds: 0,
            events: [
                PracticeSequencerMIDIEvent(
                    sourceEventID: "controller-1",
                    timeSeconds: 0,
                    kind: .controlChange(controller: 11, value: 72)
                ),
                PracticeSequencerMIDIEvent(
                    sourceEventID: "note-1",
                    timeSeconds: 0,
                    kind: .noteOn(midi: 60, velocity: 88)
                ),
            ]
        )

        try await MainActor.run {
            try playback.load(sequence: sequence)
            try playback.play(fromSeconds: 0)
        }
        try await Task.sleep(for: .milliseconds(20))

        let expected: [FakeMIDIOutputService.Call] = [
            .bytes([0xB2, 11, 72], destination: destinationUniqueID),
            .bytes([0x92, 60, 88], destination: destinationUniqueID),
        ]
        let musicalCalls = output.callsSnapshot().filter(expected.contains)
        #expect(musicalCalls == expected)
    }

    @Test func playbackQuantizesPedalsForBinaryOutputAndReportsAggregateApproximation() async throws {
        let output = FakeMIDIOutputService()
        let diagnostics = InMemoryDiagnosticsReporter()
        let destinationUniqueID: Int32 = 6789
        let playback = await MainActor.run {
            CoreMIDIPracticePlaybackService(
                destinationUniqueID: destinationUniqueID,
                outputService: output,
                diagnosticsReporter: diagnostics,
                outputCapabilities: PerformanceOutputCapabilities(
                    damper: .binary,
                    sostenuto: .binary,
                    soft: .binary
                ),
                channel: 1
            )
        }
        let sequence = PracticeSequencerSequence(
            midiData: Data(),
            durationSeconds: 0,
            events: [
                PracticeSequencerMIDIEvent(timeSeconds: 0, kind: .controlChange(controller: 64, value: 54)),
                PracticeSequencerMIDIEvent(timeSeconds: 0, kind: .controlChange(controller: 66, value: 80)),
                PracticeSequencerMIDIEvent(timeSeconds: 0, kind: .controlChange(controller: 67, value: 20)),
            ]
        )

        try await MainActor.run {
            try playback.load(sequence: sequence)
            try playback.play(fromSeconds: 0)
        }
        try await Task.sleep(for: .milliseconds(20))

        let controllerCalls = output.callsSnapshot().filter {
            if case let .bytes(bytes, _) = $0 { return bytes.first == 0xB1 }
            return false
        }
        #expect(controllerCalls == [
            .bytes([0xB1, 64, 0], destination: destinationUniqueID),
            .bytes([0xB1, 66, 127], destination: destinationUniqueID),
            .bytes([0xB1, 67, 0], destination: destinationUniqueID),
        ])
        let diagnosticEvents = await diagnostics.events
        #expect(diagnosticEvents.contains { event in
            event.stage == "coreMIDI.controllerCapability"
                && event.reason == "approximationCount=3"
        })
    }

    @Test func stopPreventsDelayedEventsFromEscapingAfterReset() async throws {
        let output = FakeMIDIOutputService()
        let destinationUniqueID: Int32 = 9012
        let playback = await MainActor.run {
            CoreMIDIPracticePlaybackService(
                destinationUniqueID: destinationUniqueID,
                outputService: output,
                channel: 0
            )
        }
        let delayedNote = PracticeSequencerMIDIEvent(
            sourceEventID: "delayed-note",
            timeSeconds: 0.2,
            kind: .noteOn(midi: 72, velocity: 80)
        )

        try await MainActor.run {
            try playback.load(sequence: PracticeSequencerSequence(
                midiData: Data(),
                durationSeconds: 0.2,
                events: [delayedNote]
            ))
            try playback.play(fromSeconds: 0)
            playback.stop(resetCommands: PerformanceTransportReducer.fullResetCommands)
        }
        let callsAfterStop = output.callsSnapshot()
        try await Task.sleep(for: .milliseconds(300))

        #expect(output.callsSnapshot() == callsAfterStop)
        #expect(output.callsSnapshot().contains(
            .bytes([0x90, 72, 80], destination: destinationUniqueID)
        ) == false)
    }

    @Test func loadAndPlayDoNotInjectResetCommands() async throws {
        let output = FakeMIDIOutputService()
        let destinationUniqueID: Int32 = 3456
        let playback = await MainActor.run {
            CoreMIDIPracticePlaybackService(
                destinationUniqueID: destinationUniqueID,
                outputService: output,
                channel: 1
            )
        }

        try await MainActor.run {
            try playback.load(sequence: PracticeSequencerSequence(
                midiData: Data(),
                durationSeconds: 1,
                events: [PracticeSequencerMIDIEvent(
                    sourceEventID: "later",
                    timeSeconds: 1,
                    kind: .noteOn(midi: 60, velocity: 70)
                )]
            ))
            try playback.play(fromSeconds: 0)
        }

        #expect(output.callsSnapshot().allSatisfy { call in
            if case .start = call { return true }
            return false
        })

        await MainActor.run {
            playback.stop(resetCommands: PerformanceTransportReducer.fullResetCommands)
        }
    }

    @Test func lookAheadSchedulerKeepsStableOrderAcrossBatchBoundary() async {
        let output = FakeMIDIOutputService()
        let clock = FakeMIDILookAheadClock()
        let scheduler = MIDILookAheadScheduler(
            outputService: output,
            destinationUniqueID: 111,
            channel: 0,
            outputCapabilities: .externalMIDI,
            hostTimeConverter: MIDIHostTimeConverter(
                currentHostTime: { 10_000 },
                hostTicksPerSecond: 1_000
            ),
            clock: clock,
            configuration: MIDILookAheadConfiguration(horizonSeconds: 0.1, refillIntervalSeconds: 0.025)
        )
        let task = scheduler.start(events: [
            PracticeSequencerMIDIEvent(timeSeconds: 0.05, kind: .noteOn(midi: 60, velocity: 80)),
            PracticeSequencerMIDIEvent(timeSeconds: 0.1, kind: .controlChange(controller: 64, value: 90)),
            PracticeSequencerMIDIEvent(timeSeconds: 0.1, kind: .noteOn(midi: 62, velocity: 81)),
            PracticeSequencerMIDIEvent(timeSeconds: 0.101, kind: .noteOff(midi: 60)),
        ], fromSeconds: 0)

        #expect(await waitUntil { output.batchesSnapshot().count == 1 && clock.sleepingCount == 1 })
        #expect(output.batchesSnapshot()[0].map(\.bytes) == [
            [0x90, 60, 80],
            [0xB0, 64, 90],
            [0x90, 62, 81],
        ])
        #expect(output.batchesSnapshot()[0].map(\.hostTime) == [10_050, 10_100, 10_100])

        clock.advance(by: 0.001)
        #expect(await waitUntil { output.batchesSnapshot().count == 2 })
        await task.value
        #expect(output.batchesSnapshot()[1] == [
            TimestampedMIDI1Message(hostTime: 10_101, bytes: [0x80, 60, 0]),
        ])
    }

    @Test func lookAheadSchedulerClampsLateEventToCurrentTransportTime() async {
        let output = FakeMIDIOutputService()
        let clock = FakeMIDILookAheadClock()
        let scheduler = MIDILookAheadScheduler(
            outputService: output,
            destinationUniqueID: 222,
            channel: 0,
            outputCapabilities: .externalMIDI,
            hostTimeConverter: MIDIHostTimeConverter(
                currentHostTime: { 20_000 },
                hostTicksPerSecond: 1_000
            ),
            clock: clock,
            configuration: MIDILookAheadConfiguration(horizonSeconds: 0.1, refillIntervalSeconds: 0.025)
        )
        let task = scheduler.start(events: [
            PracticeSequencerMIDIEvent(timeSeconds: 0, kind: .noteOn(midi: 60, velocity: 80)),
            PracticeSequencerMIDIEvent(timeSeconds: 0.2, kind: .noteOn(midi: 62, velocity: 81)),
        ], fromSeconds: 0)

        #expect(await waitUntil { output.batchesSnapshot().count == 1 && clock.sleepingCount == 1 })
        clock.advance(by: 0.25)
        #expect(await waitUntil { output.batchesSnapshot().count == 2 })
        await task.value
        #expect(output.batchesSnapshot()[1].first?.hostTime == 20_250)
    }

    @Test func cancellingLookAheadSchedulerPreventsUnsubmittedBatches() async {
        let output = FakeMIDIOutputService()
        let clock = FakeMIDILookAheadClock()
        let scheduler = MIDILookAheadScheduler(
            outputService: output,
            destinationUniqueID: 333,
            channel: 0,
            outputCapabilities: .externalMIDI,
            hostTimeConverter: MIDIHostTimeConverter(
                currentHostTime: { 30_000 },
                hostTicksPerSecond: 1_000
            ),
            clock: clock,
            configuration: MIDILookAheadConfiguration(horizonSeconds: 0.1, refillIntervalSeconds: 0.025)
        )
        let task = scheduler.start(events: [
            PracticeSequencerMIDIEvent(timeSeconds: 0, kind: .noteOn(midi: 60, velocity: 80)),
            PracticeSequencerMIDIEvent(timeSeconds: 1, kind: .noteOff(midi: 60)),
        ], fromSeconds: 0)

        #expect(await waitUntil { output.batchesSnapshot().count == 1 && clock.sleepingCount == 1 })
        task.cancel()
        await task.value
        clock.advance(by: 2)
        #expect(output.batchesSnapshot().count == 1)
    }

    @Test func invalidatedGenerationPreventsReadyBatchWithoutRelyingOnTaskCancellation() async {
        let output = FakeMIDIOutputService()
        let clock = FakeMIDILookAheadClock()
        let generationGuard = MIDIPlaybackGenerationGuard()
        let generation = generationGuard.beginGeneration()
        let scheduler = MIDILookAheadScheduler(
            outputService: output,
            destinationUniqueID: 444,
            channel: 0,
            outputCapabilities: .externalMIDI,
            hostTimeConverter: MIDIHostTimeConverter(
                currentHostTime: { 40_000 },
                hostTicksPerSecond: 1_000
            ),
            clock: clock,
            configuration: MIDILookAheadConfiguration(horizonSeconds: 0.1, refillIntervalSeconds: 0.025),
            generationGuard: generationGuard,
            generation: generation
        )
        let task = scheduler.start(events: [
            PracticeSequencerMIDIEvent(timeSeconds: 0, kind: .noteOn(midi: 60, velocity: 80)),
            PracticeSequencerMIDIEvent(timeSeconds: 0.2, kind: .noteOff(midi: 60)),
        ], fromSeconds: 0)

        #expect(await waitUntil { output.batchesSnapshot().count == 1 && clock.sleepingCount == 1 })
        generationGuard.invalidate()
        clock.advance(by: 0.25)
        await task.value
        #expect(output.batchesSnapshot().count == 1)
    }

    @Test func repeatedStartAndStopFlushOnlyActiveSchedulerGeneration() async throws {
        let output = FakeMIDIOutputService()
        let destinationUniqueID: Int32 = 555
        let playback = await MainActor.run {
            CoreMIDIPracticePlaybackService(
                destinationUniqueID: destinationUniqueID,
                outputService: output
            )
        }
        try await MainActor.run {
            try playback.load(sequence: PracticeSequencerSequence(
                midiData: Data(),
                durationSeconds: 1,
                events: [PracticeSequencerMIDIEvent(
                    timeSeconds: 0.05,
                    kind: .noteOn(midi: 60, velocity: 80)
                )]
            ))
            try playback.play(fromSeconds: 0)
        }
        #expect(await waitUntil { output.batchesSnapshot().count == 1 })

        try await MainActor.run {
            try playback.play(fromSeconds: 0)
        }
        #expect(await waitUntil { output.batchesSnapshot().count == 2 })
        await MainActor.run {
            playback.stop(resetCommands: PerformanceTransportReducer.fullResetCommands)
            playback.stop(resetCommands: PerformanceTransportReducer.fullResetCommands)
        }

        let flushCalls = output.callsSnapshot().filter {
            if case .flush = $0 { return true }
            return false
        }
        #expect(flushCalls == [
            .flush(destination: destinationUniqueID),
            .flush(destination: destinationUniqueID),
        ])
    }

    @Test func destinationRouteChangeCancelsFlushesAndResetsCurrentGeneration() async throws {
        let output = FakeMIDIOutputService()
        let destinationUniqueID: Int32 = 666
        let playback = await MainActor.run {
            CoreMIDIPracticePlaybackService(
                destinationUniqueID: destinationUniqueID,
                outputService: output
            )
        }
        try await MainActor.run {
            try playback.load(sequence: PracticeSequencerSequence(
                midiData: Data(),
                durationSeconds: 1,
                events: [
                    PracticeSequencerMIDIEvent(timeSeconds: 0, kind: .noteOn(midi: 60, velocity: 80)),
                    PracticeSequencerMIDIEvent(timeSeconds: 0.5, kind: .noteOff(midi: 60)),
                ]
            ))
            try playback.play(fromSeconds: 0)
        }
        #expect(await waitUntil { output.batchesSnapshot().count == 1 })

        output.simulateDestinationRouteChange()
        #expect(await waitUntil {
            let calls = output.callsSnapshot()
            return calls.contains(.flush(destination: destinationUniqueID)) &&
                calls.contains(.controlChange(
                    controller: 64,
                    value: 0,
                    channel: 0,
                    destination: destinationUniqueID
                )) &&
                calls.contains(.controlChange(
                    controller: 120,
                    value: 0,
                    channel: 0,
                    destination: destinationUniqueID
                ))
        })
    }

    @Test func playbackServiceTeardownFlushesAndSendsFullResetBatch() async throws {
        let output = FakeMIDIOutputService()
        let destinationUniqueID: Int32 = 777

        try await MainActor.run {
            var playback: CoreMIDIPracticePlaybackService? = CoreMIDIPracticePlaybackService(
                destinationUniqueID: destinationUniqueID,
                outputService: output,
                channel: 2
            )
            try playback?.load(sequence: PracticeSequencerSequence(
                midiData: Data(),
                durationSeconds: 1,
                events: [PracticeSequencerMIDIEvent(
                    timeSeconds: 0.5,
                    kind: .noteOn(midi: 60, velocity: 80)
                )]
            ))
            try playback?.play(fromSeconds: 0)
            playback = nil
        }

        #expect(output.callsSnapshot().contains(.flush(destination: destinationUniqueID)))
        #expect(output.batchesSnapshot().contains { batch in
            batch.map(\.bytes) == [
                [0xB2, 64, 0],
                [0xB2, 66, 0],
                [0xB2, 67, 0],
                [0xB2, 123, 0],
                [0xB2, 120, 0],
            ]
        })
    }
}

private final class FakeMIDIOutputService: MIDIOutputSendingProtocol, @unchecked Sendable {
    var onDestinationRouteWillChange: (@Sendable () -> Void)?
    var onDestinationRouteChange: (@Sendable () -> Void)?

    enum Call: Equatable {
        case start
        case stop
        case noteOn(note: UInt8, velocity: UInt8, channel: UInt8, destination: Int32)
        case noteOff(note: UInt8, channel: UInt8, destination: Int32)
        case controlChange(controller: UInt8, value: UInt8, channel: UInt8, destination: Int32)
        case programChange(program: UInt8, channel: UInt8, destination: Int32)
        case bytes([UInt8], destination: Int32)
        case flush(destination: Int32)
    }

    private let lock = OSAllocatedUnfairLock(initialState: [Call]())
    private let batchesLock = OSAllocatedUnfairLock(initialState: [[TimestampedMIDI1Message]]())
    private let failingControllers: Set<UInt8>

    init(failingControllers: Set<UInt8> = []) {
        self.failingControllers = failingControllers
    }

    func callsSnapshot() -> [Call] {
        lock.withLock { $0 }
    }

    func batchesSnapshot() -> [[TimestampedMIDI1Message]] {
        batchesLock.withLock { $0 }
    }

    func start() throws {
        lock.withLock { $0.append(.start) }
    }

    func stop() {
        lock.withLock { $0.append(.stop) }
    }

    func listDestinations() -> [MIDIDestinationInfo] {
        []
    }

    func sendMIDI1Messages(_ messages: [TimestampedMIDI1Message], destinationUniqueID: Int32) throws {
        batchesLock.withLock { $0.append(messages) }
        lock.withLock { calls in
            calls.append(contentsOf: messages.map { .bytes($0.bytes, destination: destinationUniqueID) })
        }
    }

    func flushScheduledMessages(destinationUniqueID: Int32) throws {
        lock.withLock { $0.append(.flush(destination: destinationUniqueID)) }
    }

    func simulateDestinationRouteChange() {
        onDestinationRouteWillChange?()
        onDestinationRouteChange?()
    }

    func sendNoteOn(note: UInt8, velocity: UInt8, channel: UInt8, destinationUniqueID: Int32) throws {
        lock.withLock { $0.append(.noteOn(note: note, velocity: velocity, channel: channel, destination: destinationUniqueID)) }
    }

    func sendNoteOff(note: UInt8, channel: UInt8, destinationUniqueID: Int32) throws {
        lock.withLock { $0.append(.noteOff(note: note, channel: channel, destination: destinationUniqueID)) }
    }

    func sendControlChange(controller: UInt8, value: UInt8, channel: UInt8, destinationUniqueID: Int32) throws {
        lock.withLock { $0.append(.controlChange(controller: controller, value: value, channel: channel, destination: destinationUniqueID)) }
        if failingControllers.contains(controller) {
            throw FakeMIDIOutputFailure()
        }
    }

    func sendProgramChange(program: UInt8, channel: UInt8, destinationUniqueID: Int32) throws {
        lock.withLock { $0.append(.programChange(program: program, channel: channel, destination: destinationUniqueID)) }
    }

    func sendAllNotesOff(channel: UInt8, destinationUniqueID: Int32) throws {
        try sendControlChange(controller: 123, value: 0, channel: channel, destinationUniqueID: destinationUniqueID)
    }

    func sendAllSoundOff(channel: UInt8, destinationUniqueID: Int32) throws {
        try sendControlChange(controller: 120, value: 0, channel: channel, destinationUniqueID: destinationUniqueID)
    }
}

private struct FakeMIDIOutputFailure: Error {}

private func waitForCoreMIDIResetDiagnostic(
    _ reporter: InMemoryDiagnosticsReporter
) async -> [DiagnosticEvent] {
    for _ in 0 ..< 100 {
        let events = await reporter.events
        if events.contains(where: { $0.stage == "coreMIDI.transportReset" }) {
            return events
        }
        await Task.yield()
    }
    return await reporter.events
}

private final class FakeMIDILookAheadClock: MIDILookAheadClock, @unchecked Sendable {
    private struct Sleeper {
        let deadlineSeconds: TimeInterval
        let continuation: CheckedContinuation<Void, any Error>
    }

    private struct State {
        var nowSeconds: TimeInterval = 0
        var sleepers: [UUID: Sleeper] = [:]
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())

    var sleepingCount: Int {
        lock.withLock { $0.sleepers.count }
    }

    func nowSeconds() -> TimeInterval {
        lock.withLock { $0.nowSeconds }
    }

    func sleep(for seconds: TimeInterval) async throws {
        let id = UUID()
        let deadlineSeconds = nowSeconds() + max(0, seconds)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let isCancelled = lock.withLock { state in
                    guard Task.isCancelled == false else { return true }
                    state.sleepers[id] = Sleeper(
                        deadlineSeconds: deadlineSeconds,
                        continuation: continuation
                    )
                    return false
                }
                if isCancelled {
                    continuation.resume(throwing: CancellationError())
                }
            }
        } onCancel: {
            let continuation = self.lock.withLock { state in
                state.sleepers.removeValue(forKey: id)?.continuation
            }
            continuation?.resume(throwing: CancellationError())
        }
    }

    func advance(by seconds: TimeInterval) {
        let continuations = lock.withLock { state -> [CheckedContinuation<Void, any Error>] in
            state.nowSeconds += max(0, seconds)
            let readyIDs = state.sleepers.compactMap { id, sleeper in
                sleeper.deadlineSeconds <= state.nowSeconds ? id : nil
            }
            return readyIDs.compactMap { state.sleepers.removeValue(forKey: $0)?.continuation }
        }
        for continuation in continuations {
            continuation.resume()
        }
    }
}

private func waitUntil(_ condition: @escaping @Sendable () -> Bool) async -> Bool {
    for _ in 0 ..< 1_000 {
        if condition() { return true }
        await Task.yield()
    }
    return condition()
}
