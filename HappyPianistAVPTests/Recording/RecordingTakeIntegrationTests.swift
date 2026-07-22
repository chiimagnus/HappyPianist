import Foundation
@testable import HappyPianistAVP
import Testing

@Test
func takeToMIDIDataIsNonEmpty() throws {
    let take = RecordingTake(
        name: "Export Test",
        events: [
            RecordingTakeEvent(time: 0.0, kind: .noteOn(midi: 60, velocity: 90)),
            RecordingTakeEvent(time: 0.3, kind: .noteOff(midi: 60)),
            RecordingTakeEvent(time: 0.5, kind: .noteOn(midi: 64, velocity: 80)),
            RecordingTakeEvent(time: 0.8, kind: .noteOff(midi: 64)),
        ]
    )
    let adapter = RecordingTakeSequenceAdapter()
    let sequence = try adapter.buildSequence(from: take)

    #expect(sequence.midiData.isEmpty == false)
    #expect(sequence.midiData.count > 0)
}

@Test
func takeWithMultipleNotesProducesValidMIDI() throws {
    let events = (0 ..< 10).flatMap { i -> [RecordingTakeEvent] in
        let t = Double(i) * 0.5
        return [
            RecordingTakeEvent(time: t, kind: .noteOn(midi: 60 + i, velocity: 90)),
            RecordingTakeEvent(time: t + 0.3, kind: .noteOff(midi: 60 + i)),
        ]
    }
    let take = RecordingTake(name: "Multi Note", events: events)
    let adapter = RecordingTakeSequenceAdapter()
    let sequence = try adapter.buildSequence(from: take)

    #expect(sequence.midiData.isEmpty == false)
    #expect(sequence.durationSeconds > 0)
}

@Test
func takeMetadataIncludesAlignmentDiagnostics() {
    let take = RecordingTake(name: "Diagnosed", events: [])
    let diagnostics = RecordedTakeAlignmentDiagnostics(
        takeSchemaVersion: take.schemaVersion,
        eventCount: 12,
        observationCount: 10,
        segmentCount: 0,
        alignedCount: 8,
        missingCount: 1,
        extraCount: 1,
        ambiguousCount: 2,
        unknownCount: 1,
        controllerLinkCount: 0,
        performedOccurrenceCount: 1
    )

    let text = TakeLibraryPresentationViewModel().metadataText(
        for: take,
        alignment: diagnostics
    )

    #expect(text.contains("对齐 8 · 漏 1 · 多 1 · 歧义 2 · 未知 1"))
    #expect(text.contains("/10") == false)
}

@Test
func storeClearThenLoadIsEmpty() throws {
    let documentsURL = try makeTemporaryDirectory(prefix: "RecordingIntegrationTests")
    defer { try? FileManager.default.removeItem(at: documentsURL) }

    let fileManager = TestDocumentsFileManager(documentsURL: documentsURL)
    let paths = RecordingTakeLibraryPaths(fileManager: fileManager)
    let store = RecordingTakeStore(fileManager: fileManager, paths: paths)

    let take = RecordingTake(name: "Test", events: [])
    try store.save([take])
    try store.save([])

    let loaded = try store.load()
    #expect(loaded.isEmpty)
}

@Test
func emptyTakeProducesEmptySequence() throws {
    let take = RecordingTake(name: "Empty", events: [])
    let adapter = RecordingTakeSequenceAdapter()
    let sequence = try adapter.buildSequence(from: take)

    // Empty schedule still produces valid MIDI data (header only)
    #expect(sequence.durationSeconds == 0)
}

private func makeTemporaryDirectory(prefix: String) throws -> URL {
    let directoryURL = FileManager.default.temporaryDirectory
        .appending(path: "\(prefix)-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    return directoryURL
}

private final class TestDocumentsFileManager: FileManager {
    private let documentsURL: URL

    init(documentsURL: URL) {
        self.documentsURL = documentsURL
        super.init()
    }

    override func urls(for directory: SearchPathDirectory, in domainMask: SearchPathDomainMask) -> [URL] {
        if directory == .documentDirectory {
            return [documentsURL]
        }
        return super.urls(for: directory, in: domainMask)
    }
}
