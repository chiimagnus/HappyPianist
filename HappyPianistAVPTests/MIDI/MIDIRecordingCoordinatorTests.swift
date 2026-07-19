import Foundation
@testable import HappyPianistAVP
import Testing

@Test
@MainActor
func shutdownIsIdempotentAndEmitsAtMostOneTake() {
    var recordedTakes: [RecordingTake] = []
    var states: [MIDIRecordingState.State] = []

    let clock = DeterministicPerformanceClock(start: .init(seconds: 100))
    let service = MIDIRecordingState(
        nowUptimeSeconds: { clock.now.seconds },
        nowDate: { clock.now.date },
        onStateChanged: { states.append($0) },
        onTakeRecorded: { recordedTakes.append($0) }
    )

    service.startRecordingIfPossible(canRecord: true)
    clock.advance(by: 0.25)

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
    #expect(recordedTakes[0].metadata.inputSources.first?.kind == .realPianoContact)
    #expect(recordedTakes[0].metadata.inputSources.first?.capabilities.velocity == .unavailable)
    #expect(recordedTakes[0].events.allSatisfy { $0.observation?.source.kind == .realPianoContact })
}
