import Foundation
@testable import HappyPianistAVP
import Testing

@MainActor
@Test
func recordingTeardownCancelsPendingOfflineAlignment() async {
    let probe = RecordingAlignmentCancellationProbe()
    let library = TakeLibraryViewModel(
        store: InMemoryRecordingTakeStore(),
        midiExportService: StubRecordingMIDIExportService()
    )
    let playback = TakePlaybackViewModel(
        controller: TakePlaybackController(
            playbackService: NoopPracticeSequencerPlaybackService()
        )
    )
    let viewModel = ARGuideRecordingViewModel(
        takeLibraryViewModel: library,
        takePlaybackViewModel: playback,
        alignRecordedTake: { _, _, _ in await probe.run() }
    )
    let plan = ScorePerformancePlan(
        id: .init(rawValue: "recording-cancellation"),
        sourceScoreIdentity: .init(
            songID: UUID(),
            scoreRevision: "1",
            logicalInstrumentID: "piano"
        ),
        order: .init(requested: .performed, applied: .performed),
        resolution: .init(ticksPerQuarter: 480),
        noteEvents: [],
        tempoEvents: [],
        controllerEvents: [],
        annotations: [],
        approximations: []
    )

    await viewModel.startRecording(
        canRecord: true,
        performancePlan: plan,
        measureSpans: []
    )
    viewModel.recordTakeFromKeyContactIfNeeded(
        usesBluetoothMIDIInput: false,
        isVirtualPianoEnabled: true,
        observations: [makeTestKeyContactObservation(midiNote: 60, phase: .started)]
    )
    viewModel.stopRecording()
    let didStart = await probe.waitUntilStarted()
    #expect(didStart)

    viewModel.stop()

    let didCancel = await probe.waitUntilCancelled()
    #expect(didCancel)
    #expect(viewModel.alignmentDiagnosticsByTakeID.isEmpty)
}

private actor RecordingAlignmentCancellationProbe {
    private var started = false
    private var cancelled = false

    func run() async -> RecordedTakeAlignmentDiagnostics? {
        started = true
        do {
            try await Task.sleep(for: .seconds(30))
        } catch {
            cancelled = true
        }
        return nil
    }

    func waitUntilStarted() async -> Bool {
        await waitUntil { started }
    }

    func waitUntilCancelled() async -> Bool {
        await waitUntil { cancelled }
    }

    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        // ponytail: bounded polling prevents a product failure from hanging the test indefinitely.
        for _ in 0 ..< 100 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}

private final class InMemoryRecordingTakeStore: RecordingTakeStoreProtocol {
    private var takes: [RecordingTake] = []

    func load() throws -> [RecordingTake] { takes }
    func save(_ takes: [RecordingTake]) throws { self.takes = takes }
}

private struct StubRecordingMIDIExportService: RecordingMIDIExportServiceProtocol {
    func makeMIDIExport(from _: RecordingTake) throws -> RecordingMIDIExport {
        .init(data: Data(), fileName: "take.mid")
    }
}
