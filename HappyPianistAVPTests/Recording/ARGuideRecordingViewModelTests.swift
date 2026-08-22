import Foundation
import MusicXML
import Practice
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
    private let startedEvents: AsyncStream<Void>
    private let startedEventsContinuation: AsyncStream<Void>.Continuation
    private let cancelledEvents: AsyncStream<Void>
    private let cancelledEventsContinuation: AsyncStream<Void>.Continuation

    init() {
        let started = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        startedEvents = started.stream
        startedEventsContinuation = started.continuation

        let cancelled = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        cancelledEvents = cancelled.stream
        cancelledEventsContinuation = cancelled.continuation
    }

    func run() async -> RecordedTakeAlignmentDiagnostics? {
        startedEventsContinuation.yield()
        do {
            try await Task.sleep(for: .seconds(30))
        } catch {
            cancelledEventsContinuation.yield()
        }
        return nil
    }

    func waitUntilStarted() async -> Bool {
        await wait(for: startedEvents)
    }

    func waitUntilCancelled() async -> Bool {
        await wait(for: cancelledEvents)
    }

    private func wait(for events: AsyncStream<Void>) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                var iterator = events.makeAsyncIterator()
                return await iterator.next() != nil
            }
            group.addTask {
                (try? await Task.sleep(for: .seconds(1))) != nil
            }

            guard let result = await group.next() else { return false }
            group.cancelAll()
            return result
        }
    }
}

private final class InMemoryRecordingTakeStore: RecordingTakeStoreProtocol {
    private var takes: [RecordingTake] = []

    func load() throws -> [RecordingTake] {
        takes
    }

    func save(_ takes: [RecordingTake]) throws {
        self.takes = takes
    }
}

private struct StubRecordingMIDIExportService: RecordingMIDIExportServiceProtocol {
    func makeMIDIExport(from _: RecordingTake) throws -> RecordingMIDIExport {
        .init(data: Data(), fileName: "take.mid")
    }
}
