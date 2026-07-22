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
func recordTakeFromKeyContactRequiresRecordingAndNonBluetooth() throws {
    var recordedTakes: [RecordingTake] = []
    let scoreIdentity = ScorePerformanceSourceIdentity(
        songID: try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111")),
        scoreRevision: "sha256:test-score",
        logicalInstrumentID: "P1:piano"
    )

    let service = MIDIRecordingState(
        nowUptimeSeconds: { 0 },
        nowDate: { Date(timeIntervalSince1970: 0) },
        onStateChanged: { _ in },
        onTakeRecorded: { recordedTakes.append($0) }
    )

    service.recordTakeFromKeyContactIfNeeded(
        usesBluetoothMIDIInput: false,
        isVirtualPianoEnabled: false,
        observations: makeTestKeyContactObservations(startedMIDINotes: [60], endedMIDINotes: [60])
    )
    service.stopRecordingIfNeeded()
    #expect(recordedTakes.isEmpty)

    service.startRecordingIfPossible(canRecord: true)
    service.recordTakeFromKeyContactIfNeeded(
        usesBluetoothMIDIInput: true,
        isVirtualPianoEnabled: false,
        observations: makeTestKeyContactObservations(startedMIDINotes: [60], endedMIDINotes: [60])
    )
    service.stopRecordingIfNeeded()
    #expect(recordedTakes.isEmpty)

    service.startRecordingIfPossible(
        canRecord: true,
        metadata: RecordingTakeMetadata(
            scoreIdentity: scoreIdentity,
            inputSources: RecordingTakeMetadata.unattributed.inputSources
        )
    )
    service.recordTakeFromKeyContactIfNeeded(
        usesBluetoothMIDIInput: false,
        isVirtualPianoEnabled: false,
        observations: makeTestKeyContactObservations(
            startedMIDINotes: [60],
            endedMIDINotes: [60],
            startedVelocity: 73
        )
    )
    service.stopRecordingIfNeeded()
    #expect(recordedTakes.count == 1)
    #expect(recordedTakes[0].events.isEmpty == false)
    #expect(recordedTakes[0].metadata.scoreIdentity == scoreIdentity)
    #expect(recordedTakes[0].metadata.inputSources.first?.kind == .realPianoContact)
    #expect(recordedTakes[0].metadata.inputSources.first?.capabilities.velocity == .degraded)
    #expect(recordedTakes[0].events.allSatisfy { $0.observation?.source.kind == .realPianoContact })
    #expect(recordedTakes[0].events.first?.kind == .noteOn(midi: 60, velocity: 73))
    let observation = try #require(recordedTakes[0].events.first?.observation)
    #expect(observation.hand != nil)
    #expect(observation.finger != nil)
    #expect(observation.onsetVelocity == .init(midi1: 73))
    #expect(observation.calibrationReference != nil)
}

@Test
@MainActor
func virtualPianoTakeUsesResolvedContactVelocity() {
    var recordedTakes: [RecordingTake] = []
    let service = MIDIRecordingState(
        nowUptimeSeconds: { 0 },
        nowDate: { Date(timeIntervalSince1970: 0) },
        onStateChanged: { _ in },
        onTakeRecorded: { recordedTakes.append($0) }
    )
    service.startRecordingIfPossible(canRecord: true)
    service.recordTakeFromKeyContactIfNeeded(
        usesBluetoothMIDIInput: false,
        isVirtualPianoEnabled: true,
        observations: makeTestKeyContactObservations(
            startedMIDINotes: [64],
            endedMIDINotes: [64],
            startedVelocity: 106
        )
    )
    service.stopRecordingIfNeeded()

    #expect(recordedTakes.first?.events.first?.kind == .noteOn(midi: 64, velocity: 106))
    #expect(recordedTakes.first?.metadata.inputSources.first?.kind == .virtualPianoContact)
}
