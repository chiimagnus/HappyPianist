import Foundation
import Diagnostics
import MIDI
@testable import HappyPianistAVP
import os
import Testing

struct CoreMIDIPracticePlaybackServiceStopTests {
    @Test func stopExecutesReducerResetCommandsInOrder() async throws {
        let output = FakePerformanceOutput()
        let destinationUniqueID: Int32 = 1234
        let plan = makeTestScorePerformancePlan(notes: [
            TestScorePerformanceNote(midiNote: 60, onTick: 0),
        ])
        let eventID = plan.noteEvents[0].id
        let playback = await MainActor.run {
            CoreMIDIPracticePlaybackService(destinationUniqueID: destinationUniqueID, outputService: output, channel: 0)
        }

        try await playback.load(sequence: PracticeSequencerSequence(
            midiData: Data(),
            durationSeconds: 1,
            events: [PracticeSequencerMIDIEvent(
                sourceEventID: eventID.description,
                timeSeconds: 0,
                kind: .noteOn(midi: 60, velocity: 96)
            )]
        ))
        let callCountBeforeStop = output.callsSnapshot().count
        await playback.stop(resetCommands: PerformanceTransportReducer.resetCommands(eventIDs: [eventID]))

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
        let output = FakePerformanceOutput(failingControllers: [64, 120])
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

        await playback.stop(resetCommands: PerformanceTransportReducer.fullResetCommands)

        let controllers = output.callsSnapshot().compactMap { call -> UInt8? in
            guard case let .controlChange(controller, _, _, _) = call else { return nil }
            return controller
        }
        #expect(controllers == [64, 66, 67, 123, 120])
        let events = await waitForDiagnostics(diagnostics) { events in
            events.contains { $0.stage == "coreMIDI.transportReset" }
        }
        #expect(events.contains { event in
            event.stage == "coreMIDI.transportReset"
                && event.reason == "failureCount=2"
        })
    }

    @Test func playbackSendsCanonicalSequenceEventsIncludingControllers() async throws {
        let output = FakePerformanceOutput()
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

        try await playback.load(sequence: sequence)
        try await playback.play(fromSeconds: 0)
        try await Task.sleep(for: .milliseconds(20))

        let expected: [FakePerformanceOutput.Call] = [
            .bytes([0xB2, 11, 72], destination: destinationUniqueID),
            .bytes([0x92, 60, 88], destination: destinationUniqueID),
        ]
        let musicalCalls = output.callsSnapshot().filter(expected.contains)
        #expect(musicalCalls == expected)
    }

    @Test func playbackQuantizesPedalsForBinaryOutputAndReportsAggregateApproximation() async throws {
        let capabilities = PerformanceOutputCapabilities(
            damper: .binary,
            sostenuto: .binary,
            soft: .binary
        )
        let output = FakePerformanceOutput(capabilities: capabilities)
        let diagnostics = InMemoryDiagnosticsReporter()
        let destinationUniqueID: Int32 = 6789
        let playback = await MainActor.run {
            CoreMIDIPracticePlaybackService(
                destinationUniqueID: destinationUniqueID,
                outputService: output,
                diagnosticsReporter: diagnostics,
                outputCapabilities: capabilities,
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

        try await playback.load(sequence: sequence)
        try await playback.play(fromSeconds: 0)
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
        let output = FakePerformanceOutput()
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

        try await playback.load(sequence: PracticeSequencerSequence(
            midiData: Data(),
            durationSeconds: 0.2,
            events: [delayedNote]
        ))
        try await playback.play(fromSeconds: 0)
        await playback.stop(resetCommands: PerformanceTransportReducer.fullResetCommands)
        let callsAfterStop = output.callsSnapshot()
        try await Task.sleep(for: .milliseconds(300))

        #expect(output.callsSnapshot() == callsAfterStop)
        #expect(output.callsSnapshot().contains(
            .bytes([0x90, 72, 80], destination: destinationUniqueID)
        ) == false)
    }

    @Test func loadAndPlayDoNotInjectResetCommands() async throws {
        let output = FakePerformanceOutput()
        let destinationUniqueID: Int32 = 3456
        let playback = await MainActor.run {
            CoreMIDIPracticePlaybackService(
                destinationUniqueID: destinationUniqueID,
                outputService: output,
                channel: 1
            )
        }

        try await playback.load(sequence: PracticeSequencerSequence(
            midiData: Data(),
            durationSeconds: 1,
            events: [PracticeSequencerMIDIEvent(
                sourceEventID: "later",
                timeSeconds: 1,
                kind: .noteOn(midi: 60, velocity: 70)
            )]
        ))
        try await playback.play(fromSeconds: 0)

        #expect(output.callsSnapshot().allSatisfy { call in
            if case .start = call { return true }
            return false
        })

        await playback.stop(resetCommands: PerformanceTransportReducer.fullResetCommands)
    }

    @Test func readyCoreMIDIOutputStartsOnlyOnceAcrossHotPaths() async throws {
        let output = FakePerformanceOutput()
        let playback = await MainActor.run {
            CoreMIDIPracticePlaybackService(destinationUniqueID: 3457, outputService: output)
        }

        try await playback.warmUp()
        try await playback.load(sequence: PracticeSequencerSequence(
            midiData: Data(),
            durationSeconds: 0,
            events: []
        ))
        try await playback.play(fromSeconds: 0)
        try await playback.execute(commands: [
            PracticePlaybackCommand(
                sourceEventID: "live-program",
                kind: .programChange(program: 1)
            ),
        ])

        #expect(output.callsSnapshot().count(where: { $0 == .start }) == 1)
    }

    @Test func lookAheadSchedulerKeepsStableOrderAcrossBatchBoundary() async {
        let output = FakePerformanceOutput()
        let clock = FakeMIDILookAheadClock()
        let scheduler = MIDILookAheadScheduler(
            outputService: output,
            destinationUniqueID: 111,
            channel: 0,
            outputCapabilities: output.capabilities,
            hostTimeConverter: MIDIHostTimeConverter(
                currentHostTime: { 10000 },
                hostTicksPerSecond: 1000
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

        #expect(await waitUntil { output.timestampedBatchesSnapshot().count == 1 && await clock.sleepingCount == 1 })
        #expect(output.timestampedBatchesSnapshot()[0].messages.map(\.bytes) == [
            [0x90, 60, 80],
            [0xB0, 64, 90],
            [0x90, 62, 81],
        ])
        #expect(output.timestampedBatchesSnapshot()[0].messages.map(\.hostTime) == [10050, 10100, 10100])

        await clock.advance(by: 0.002)
        #expect(await waitUntil { output.timestampedBatchesSnapshot().count == 2 })
        await task.value
        #expect(output.timestampedBatchesSnapshot()[1].messages == [
            TimestampedMIDI1Message(hostTime: 10101, bytes: [0x80, 60, 0]),
        ])
    }

    @Test func lookAheadSchedulerClampsLateEventToCurrentTransportTime() async {
        let output = FakePerformanceOutput()
        let clock = FakeMIDILookAheadClock()
        let diagnostics = InMemoryDiagnosticsReporter()
        let scheduler = MIDILookAheadScheduler(
            outputService: output,
            destinationUniqueID: 222,
            channel: 0,
            outputCapabilities: output.capabilities,
            hostTimeConverter: MIDIHostTimeConverter(
                currentHostTime: { 20000 },
                hostTicksPerSecond: 1000
            ),
            clock: clock,
            configuration: MIDILookAheadConfiguration(horizonSeconds: 0.1, refillIntervalSeconds: 0.025),
            diagnosticsReporter: diagnostics
        )
        let task = scheduler.start(events: [
            PracticeSequencerMIDIEvent(timeSeconds: 0, kind: .noteOn(midi: 60, velocity: 80)),
            PracticeSequencerMIDIEvent(timeSeconds: 0.2, kind: .noteOn(midi: 62, velocity: 81)),
        ], fromSeconds: 0)

        #expect(await waitUntil { output.timestampedBatchesSnapshot().count == 1 && await clock.sleepingCount == 1 })
        await clock.advance(by: 0.25)
        #expect(await waitUntil { output.timestampedBatchesSnapshot().count == 2 })
        await task.value
        #expect(output.timestampedBatchesSnapshot()[1].messages.first?.hostTime == 20250)
        let events = await waitForDiagnostics(diagnostics) { events in
            events.contains { $0.stage == "playback.outputMetrics" }
        }
        #expect(events.contains { event in
            event.stage == "playback.outputMetrics"
                && event.reason.contains("scheduled=2")
                && event.reason.contains("submitted=2")
                && event.reason.contains("acknowledged=0")
                && event.reason.contains("late=1")
        })
    }

    @Test func cancellingLookAheadSchedulerPreventsUnsubmittedBatches() async {
        let output = FakePerformanceOutput()
        let clock = FakeMIDILookAheadClock()
        let scheduler = MIDILookAheadScheduler(
            outputService: output,
            destinationUniqueID: 333,
            channel: 0,
            outputCapabilities: output.capabilities,
            hostTimeConverter: MIDIHostTimeConverter(
                currentHostTime: { 30000 },
                hostTicksPerSecond: 1000
            ),
            clock: clock,
            configuration: MIDILookAheadConfiguration(horizonSeconds: 0.1, refillIntervalSeconds: 0.025)
        )
        let task = scheduler.start(events: [
            PracticeSequencerMIDIEvent(timeSeconds: 0, kind: .noteOn(midi: 60, velocity: 80)),
            PracticeSequencerMIDIEvent(timeSeconds: 1, kind: .noteOff(midi: 60)),
        ], fromSeconds: 0)

        #expect(await waitUntil { output.timestampedBatchesSnapshot().count == 1 && await clock.sleepingCount == 1 })
        task.cancel()
        await task.value
        await clock.advance(by: 2)
        #expect(output.timestampedBatchesSnapshot().count == 1)
    }

    @Test func lookAheadSendFailureDropsRemainingGenerationAndReportsMetrics() async {
        let output = FakePerformanceOutput()
        output.failNextMIDIBatch()
        let diagnostics = InMemoryDiagnosticsReporter()
        let scheduler = MIDILookAheadScheduler(
            outputService: output,
            destinationUniqueID: 334,
            channel: 0,
            outputCapabilities: output.capabilities,
            hostTimeConverter: MIDIHostTimeConverter(
                currentHostTime: { 35000 },
                hostTicksPerSecond: 1000
            ),
            diagnosticsReporter: diagnostics
        )

        let task = scheduler.start(events: [
            PracticeSequencerMIDIEvent(timeSeconds: 0, kind: .noteOn(midi: 60, velocity: 80)),
            PracticeSequencerMIDIEvent(timeSeconds: 0.05, kind: .noteOff(midi: 60)),
        ], fromSeconds: 0)
        await task.value

        #expect(output.timestampedBatchesSnapshot().count == 1)
        let events = await waitForDiagnostics(diagnostics) { events in
            events.contains { $0.stage == "playback.outputMetrics" }
        }
        #expect(events.contains { event in
            event.stage == "playback.outputMetrics"
                && event.reason.contains("scheduled=2")
                && event.reason.contains("submitted=0")
                && event.reason.contains("dropped=2")
        })
    }

    @Test func invalidatedGenerationPreventsReadyBatchWithoutRelyingOnTaskCancellation() async {
        let generationGate = MIDIPlaybackGenerationGate()
        let generation = generationGate.beginGeneration()
        let output = FakePerformanceOutput(generation: { generation })
        let clock = FakeMIDILookAheadClock()
        let scheduler = MIDILookAheadScheduler(
            outputService: output,
            destinationUniqueID: 444,
            channel: 0,
            outputCapabilities: output.capabilities,
            hostTimeConverter: MIDIHostTimeConverter(
                currentHostTime: { 40000 },
                hostTicksPerSecond: 1000
            ),
            clock: clock,
            configuration: MIDILookAheadConfiguration(horizonSeconds: 0.1, refillIntervalSeconds: 0.025),
            generationGate: generationGate,
            generation: generation
        )
        let task = scheduler.start(events: [
            PracticeSequencerMIDIEvent(timeSeconds: 0, kind: .noteOn(midi: 60, velocity: 80)),
            PracticeSequencerMIDIEvent(timeSeconds: 0.2, kind: .noteOff(midi: 60)),
        ], fromSeconds: 0)

        #expect(await waitUntil { output.timestampedBatchesSnapshot().count == 1 && await clock.sleepingCount == 1 })
        #expect(output.timestampedBatchesSnapshot().first?.generation == generation)
        #expect(output.timestampedBatchesSnapshot().first?.capabilities == .externalMIDI)
        generationGate.invalidate()
        await clock.advance(by: 0.25)
        await task.value
        #expect(output.timestampedBatchesSnapshot().count == 1)
    }

    @Test func repeatedStartAndStopFlushOnlyActiveSchedulerGeneration() async throws {
        let output = FakePerformanceOutput()
        let destinationUniqueID: Int32 = 555
        let playback = await MainActor.run {
            CoreMIDIPracticePlaybackService(
                destinationUniqueID: destinationUniqueID,
                outputService: output
            )
        }
        try await playback.load(sequence: PracticeSequencerSequence(
            midiData: Data(),
            durationSeconds: 1,
            events: [PracticeSequencerMIDIEvent(
                timeSeconds: 0.05,
                kind: .noteOn(midi: 60, velocity: 80)
            )]
        ))
        try await playback.play(fromSeconds: 0)
        #expect(await waitUntil { output.timestampedBatchesSnapshot().count == 1 })

        try await playback.play(fromSeconds: 0)
        #expect(await waitUntil { output.timestampedBatchesSnapshot().count == 2 })
        await playback.stop(resetCommands: PerformanceTransportReducer.fullResetCommands)
        await playback.stop(resetCommands: PerformanceTransportReducer.fullResetCommands)

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
        let output = FakePerformanceOutput()
        let destinationUniqueID: Int32 = 666
        let playback = await MainActor.run {
            CoreMIDIPracticePlaybackService(
                destinationUniqueID: destinationUniqueID,
                outputService: output
            )
        }
        try await playback.load(sequence: PracticeSequencerSequence(
            midiData: Data(),
            durationSeconds: 1,
            events: [
                PracticeSequencerMIDIEvent(timeSeconds: 0, kind: .noteOn(midi: 60, velocity: 80)),
                PracticeSequencerMIDIEvent(timeSeconds: 0.5, kind: .noteOff(midi: 60)),
            ]
        ))
        try await playback.play(fromSeconds: 0)
        #expect(await waitUntil { output.timestampedBatchesSnapshot().count == 1 })

        await output.simulateDestinationDisconnect()
        let calls = output.callsSnapshot()
        #expect(calls.contains(.flush(destination: destinationUniqueID)))
        #expect(calls.contains(.controlChange(
            controller: 64,
            value: 0,
            channel: 0,
            destination: destinationUniqueID
        )))
        #expect(calls.contains(.controlChange(
            controller: 120,
            value: 0,
            channel: 0,
            destination: destinationUniqueID
        )))
    }

    @Test func destinationRouteChangeResetsLiveOutputWithoutScheduler() async throws {
        let output = FakePerformanceOutput()
        let destinationUniqueID: Int32 = 667
        let playback = await MainActor.run {
            CoreMIDIPracticePlaybackService(
                destinationUniqueID: destinationUniqueID,
                outputService: output
            )
        }
        try await playback.execute(commands: [
            PracticePlaybackCommand(
                sourceEventID: "live-note",
                kind: .noteOn(midi: 60, velocity: 80)
            ),
            PracticePlaybackCommand(
                sourceEventID: "live-pedal",
                kind: .controlChange(controller: 64, value: 127)
            ),
        ])

        await output.simulateDestinationDisconnect()

        #expect(Array(output.callsSnapshot().suffix(5)) == [
            .controlChange(controller: 64, value: 0, channel: 0, destination: destinationUniqueID),
            .controlChange(controller: 66, value: 0, channel: 0, destination: destinationUniqueID),
            .controlChange(controller: 67, value: 0, channel: 0, destination: destinationUniqueID),
            .controlChange(controller: 123, value: 0, channel: 0, destination: destinationUniqueID),
            .controlChange(controller: 120, value: 0, channel: 0, destination: destinationUniqueID),
        ])
    }

    @Test func playbackServiceTeardownFlushesAndSendsFullResetBatch() async throws {
        let output = FakePerformanceOutput()
        let destinationUniqueID: Int32 = 777

        try await createAndReleaseScheduledPlayback(
            destinationUniqueID: destinationUniqueID,
            output: output
        )

        #expect(output.callsSnapshot().contains(.flush(destination: destinationUniqueID)))
        #expect(Array(output.callsSnapshot().suffix(5)) == [
            .controlChange(controller: 64, value: 0, channel: 2, destination: destinationUniqueID),
            .controlChange(controller: 66, value: 0, channel: 2, destination: destinationUniqueID),
            .controlChange(controller: 67, value: 0, channel: 2, destination: destinationUniqueID),
            .controlChange(controller: 123, value: 0, channel: 2, destination: destinationUniqueID),
            .controlChange(controller: 120, value: 0, channel: 2, destination: destinationUniqueID),
        ])
    }

    @Test func playbackServiceTeardownResetsLiveOutputWithoutScheduler() async throws {
        let output = FakePerformanceOutput()
        let destinationUniqueID: Int32 = 778

        try await createAndReleaseLivePlayback(
            destinationUniqueID: destinationUniqueID,
            output: output
        )

        #expect(Array(output.callsSnapshot().suffix(5)) == [
            .controlChange(controller: 64, value: 0, channel: 3, destination: destinationUniqueID),
            .controlChange(controller: 66, value: 0, channel: 3, destination: destinationUniqueID),
            .controlChange(controller: 67, value: 0, channel: 3, destination: destinationUniqueID),
            .controlChange(controller: 123, value: 0, channel: 3, destination: destinationUniqueID),
            .controlChange(controller: 120, value: 0, channel: 3, destination: destinationUniqueID),
        ])
        let callsAfterTeardown = output.callsSnapshot()
        await output.simulateDestinationDisconnect()
        #expect(output.callsSnapshot() == callsAfterTeardown)
    }
}

@MainActor
private func createAndReleaseScheduledPlayback(
    destinationUniqueID: Int32,
    output: FakePerformanceOutput
) async throws {
    var playback: CoreMIDIPracticePlaybackService? = CoreMIDIPracticePlaybackService(
        destinationUniqueID: destinationUniqueID,
        outputService: output,
        channel: 2
    )
    try await playback?.load(sequence: PracticeSequencerSequence(
        midiData: Data(),
        durationSeconds: 1,
        events: [PracticeSequencerMIDIEvent(
            timeSeconds: 0.5,
            kind: .noteOn(midi: 60, velocity: 80)
        )]
    ))
    try await playback?.play(fromSeconds: 0)
    playback = nil
}

@MainActor
private func createAndReleaseLivePlayback(
    destinationUniqueID: Int32,
    output: FakePerformanceOutput
) async throws {
    var playback: CoreMIDIPracticePlaybackService? = CoreMIDIPracticePlaybackService(
        destinationUniqueID: destinationUniqueID,
        outputService: output,
        channel: 3
    )
    try await playback?.execute(commands: [
        PracticePlaybackCommand(
            sourceEventID: "preview-note",
            kind: .noteOn(midi: 65, velocity: 70)
        ),
    ])
    playback = nil
}

private func waitForDiagnostics(
    _ reporter: InMemoryDiagnosticsReporter,
    until condition: @escaping @Sendable ([DiagnosticEvent]) -> Bool
) async -> [DiagnosticEvent] {
    let clock = ContinuousClock()
    let deadline = clock.now + .seconds(1)
    while clock.now < deadline {
        let events = await reporter.events
        if condition(events) { return events }
        do {
            try await Task.sleep(for: .milliseconds(1))
        } catch {
            return events
        }
    }
    return await reporter.events
}

private actor FakeMIDILookAheadClock: MIDILookAheadClock {
    private struct Sleeper {
        let deadlineSeconds: TimeInterval
        let continuation: CheckedContinuation<Void, any Error>
    }

    private struct State {
        var nowSeconds: TimeInterval = 0
        var sleepers: [UUID: Sleeper] = [:]
    }

    private var state = State()

    var sleepingCount: Int {
        state.sleepers.count
    }

    func nowSeconds() -> TimeInterval {
        state.nowSeconds
    }

    func sleep(for seconds: TimeInterval) async throws {
        let id = UUID()
        let deadlineSeconds = state.nowSeconds + max(0, seconds)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard Task.isCancelled == false else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                state.sleepers[id] = Sleeper(
                    deadlineSeconds: deadlineSeconds,
                    continuation: continuation
                )
            }
        } onCancel: {
            Task { await self.cancelSleep(id: id) }
        }
    }

    func advance(by seconds: TimeInterval) {
        state.nowSeconds += max(0, seconds)
        let readyIDs = state.sleepers.compactMap { id, sleeper in
            sleeper.deadlineSeconds <= state.nowSeconds ? id : nil
        }
        let continuations = readyIDs.compactMap { state.sleepers.removeValue(forKey: $0)?.continuation }
        for continuation in continuations {
            continuation.resume()
        }
    }

    private func cancelSleep(id: UUID) {
        state.sleepers.removeValue(forKey: id)?.continuation.resume(throwing: CancellationError())
    }
}

private func waitUntil(_ condition: @escaping @Sendable () async -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + .seconds(1)
    while clock.now < deadline {
        if await condition() { return true }
        do {
            try await Task.sleep(for: .milliseconds(1))
        } catch {
            return await condition()
        }
    }
    return await condition()
}
