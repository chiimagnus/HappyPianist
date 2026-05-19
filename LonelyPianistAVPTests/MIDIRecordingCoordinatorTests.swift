import Foundation
@testable import LonelyPianistAVP
import Testing
import os

@Test
@MainActor
func shutdownIsIdempotentAndEmitsAtMostOneTake() async {
    var recordedTakes: [RecordingTake] = []
    var states: [MIDIRecordingCoordinator.State] = []

    let coordinator = MIDIRecordingCoordinator(
        logger: Logger(subsystem: "test", category: "midi-recording"),
        nowUptimeSeconds: { 100 },
        nowDate: { Date(timeIntervalSince1970: 0) },
        onStateChanged: { states.append($0) },
        onTakeRecorded: { recordedTakes.append($0) }
    )

    coordinator.startRecordingIfPossible(canRecord: true)

    coordinator.shutdown()
    coordinator.shutdown()

    #expect(states.contains(where: { $0.isRecording }))
    #expect(states.last?.isRecording == false)
    #expect(recordedTakes.count <= 1)
}

@Test
@MainActor
func recordTakeFromKeyContactRequiresRecordingAndNonBluetooth() {
    var recordedTakes: [RecordingTake] = []

    let coordinator = MIDIRecordingCoordinator(
        logger: Logger(subsystem: "test", category: "midi-recording"),
        nowUptimeSeconds: { 0 },
        nowDate: { Date(timeIntervalSince1970: 0) },
        onStateChanged: { _ in },
        onTakeRecorded: { recordedTakes.append($0) }
    )

    coordinator.recordTakeFromKeyContactIfNeeded(
        usesBluetoothMIDIInput: false,
        isVirtualPianoEnabled: false,
        keyContact: KeyContactResult(down: [], started: [60], ended: [60]),
        nowUptimeSeconds: 1
    )
    coordinator.stopRecordingIfNeeded()
    #expect(recordedTakes.isEmpty)

    coordinator.startRecordingIfPossible(canRecord: true)
    coordinator.recordTakeFromKeyContactIfNeeded(
        usesBluetoothMIDIInput: true,
        isVirtualPianoEnabled: false,
        keyContact: KeyContactResult(down: [], started: [60], ended: [60]),
        nowUptimeSeconds: 1
    )
    coordinator.stopRecordingIfNeeded()
    #expect(recordedTakes.isEmpty)

    coordinator.startRecordingIfPossible(canRecord: true)
    coordinator.recordTakeFromKeyContactIfNeeded(
        usesBluetoothMIDIInput: false,
        isVirtualPianoEnabled: false,
        keyContact: KeyContactResult(down: [], started: [60], ended: [60]),
        nowUptimeSeconds: 1
    )
    coordinator.stopRecordingIfNeeded()
    #expect(recordedTakes.count == 1)
    #expect(recordedTakes[0].events.isEmpty == false)
}

