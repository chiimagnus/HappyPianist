import Foundation
@testable import LonelyPianistAVP
import os
import Testing

@Test
@MainActor
func shutdownIsIdempotentAndEmitsAtMostOneTake() {
    var recordedTakes: [RecordingTake] = []
    var states: [MIDIRecordingState.State] = []

    let service = MIDIRecordingState(
        logger: Logger(subsystem: "test", category: "midi-recording"),
        nowUptimeSeconds: { 100 },
        nowDate: { Date(timeIntervalSince1970: 0) },
        onStateChanged: { states.append($0) },
        onTakeRecorded: { recordedTakes.append($0) }
    )

    service.startRecordingIfPossible(canRecord: true)

    service.shutdown()
    service.shutdown()

    let didRecord = states.contains { $0.isRecording }
    #expect(didRecord)
    #expect(states.last?.isRecording == false)
    #expect(recordedTakes.count <= 1)
}

@Test
@MainActor
func recordTakeFromKeyContactRequiresRecordingAndNonBluetooth() {
    var recordedTakes: [RecordingTake] = []

    let service = MIDIRecordingState(
        logger: Logger(subsystem: "test", category: "midi-recording"),
        nowUptimeSeconds: { 0 },
        nowDate: { Date(timeIntervalSince1970: 0) },
        onStateChanged: { _ in },
        onTakeRecorded: { recordedTakes.append($0) }
    )

    service.recordTakeFromKeyContactIfNeeded(
        usesBluetoothMIDIInput: false,
        isVirtualPianoEnabled: false,
        keyContact: KeyContactResult(down: [], started: [60], ended: [60]),
        nowUptimeSeconds: 1
    )
    service.stopRecordingIfNeeded()
    #expect(recordedTakes.isEmpty)

    service.startRecordingIfPossible(canRecord: true)
    service.recordTakeFromKeyContactIfNeeded(
        usesBluetoothMIDIInput: true,
        isVirtualPianoEnabled: false,
        keyContact: KeyContactResult(down: [], started: [60], ended: [60]),
        nowUptimeSeconds: 1
    )
    service.stopRecordingIfNeeded()
    #expect(recordedTakes.isEmpty)

    service.startRecordingIfPossible(canRecord: true)
    service.recordTakeFromKeyContactIfNeeded(
        usesBluetoothMIDIInput: false,
        isVirtualPianoEnabled: false,
        keyContact: KeyContactResult(down: [], started: [60], ended: [60]),
        nowUptimeSeconds: 1
    )
    service.stopRecordingIfNeeded()
    #expect(recordedTakes.count == 1)
    #expect(recordedTakes[0].events.isEmpty == false)
}
