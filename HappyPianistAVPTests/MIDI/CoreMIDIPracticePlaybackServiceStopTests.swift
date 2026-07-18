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
            CoreMIDIPracticePlaybackService(destinationUniqueID: destinationUniqueID, outputService: output, velocity: 96, channel: 0)
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

    @Test func playbackSendsCanonicalSequenceEventsIncludingControllers() async throws {
        let output = FakeMIDIOutputService()
        let destinationUniqueID: Int32 = 5678
        let playback = await MainActor.run {
            CoreMIDIPracticePlaybackService(
                destinationUniqueID: destinationUniqueID,
                outputService: output,
                velocity: 96,
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
                velocity: 96,
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
                velocity: 96,
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
}

private final class FakeMIDIOutputService: MIDIOutputSendingProtocol, @unchecked Sendable {
    enum Call: Equatable {
        case start
        case stop
        case noteOn(note: UInt8, velocity: UInt8, channel: UInt8, destination: Int32)
        case noteOff(note: UInt8, channel: UInt8, destination: Int32)
        case controlChange(controller: UInt8, value: UInt8, channel: UInt8, destination: Int32)
        case programChange(program: UInt8, channel: UInt8, destination: Int32)
        case bytes([UInt8], destination: Int32)
    }

    private let lock = OSAllocatedUnfairLock(initialState: [Call]())

    func callsSnapshot() -> [Call] {
        lock.withLock { $0 }
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
        lock.withLock { calls in
            calls.append(contentsOf: messages.map { .bytes($0.bytes, destination: destinationUniqueID) })
        }
    }

    func sendNoteOn(note: UInt8, velocity: UInt8, channel: UInt8, destinationUniqueID: Int32) throws {
        lock.withLock { $0.append(.noteOn(note: note, velocity: velocity, channel: channel, destination: destinationUniqueID)) }
    }

    func sendNoteOff(note: UInt8, channel: UInt8, destinationUniqueID: Int32) throws {
        lock.withLock { $0.append(.noteOff(note: note, channel: channel, destination: destinationUniqueID)) }
    }

    func sendControlChange(controller: UInt8, value: UInt8, channel: UInt8, destinationUniqueID: Int32) throws {
        lock.withLock { $0.append(.controlChange(controller: controller, value: value, channel: channel, destination: destinationUniqueID)) }
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
