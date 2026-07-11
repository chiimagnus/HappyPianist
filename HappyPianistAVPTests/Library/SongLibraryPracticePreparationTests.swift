import Foundation
@testable import HappyPianistAVP
import Testing

private actor DelayedPreparationService: PracticePreparationServiceProtocol {
    let delays: [UUID: Duration]

    init(delays: [UUID: Duration]) {
        self.delays = delays
    }

    func prepare(songID: UUID, from _: URL, file: ImportedMusicXMLFile) async throws -> PreparedPractice {
        if let delay = delays[songID] {
            try await Task.sleep(for: delay)
        }
        return PreparedPractice(
            identity: PracticeSongIdentity(songID: songID, scoreRevision: songID.uuidString),
            steps: [PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1)])],
            file: file,
            tempoMap: MusicXMLTempoMap(tempoEvents: []),
            pedalTimeline: nil,
            fermataTimeline: nil,
            attributeTimeline: nil,
            slurTimeline: nil,
            highlightGuides: [],
            measureSpans: [],
            unsupportedNoteCount: 0
        )
    }
}

private struct PreparationTestBundledProvider: BundledSongLibraryProviderProtocol {
    let entries: [SongLibraryEntry]
    let scoreURL: URL

    func bundledEntries() -> [SongLibraryEntry] { entries }
    func musicXMLURL(fileName _: String) -> URL? { scoreURL }
    func audioURL(fileName _: String) -> URL? { nil }
}

@Test
@MainActor
func latestPreparationGenerationWins() async throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "generation-\(UUID().uuidString).musicxml")
    try Data("<score-partwise/>".utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let firstID = UUID()
    let secondID = UUID()
    let entries = [
        SongLibraryEntry(id: firstID, displayName: "First", musicXMLFileName: "first.musicxml", importedAt: .now, audioFileName: nil, isBundled: true),
        SongLibraryEntry(id: secondID, displayName: "Second", musicXMLFileName: "second.musicxml", importedAt: .now, audioFileName: nil, isBundled: true),
    ]
    let service = DelayedPreparationService(delays: [firstID: .milliseconds(80), secondID: .milliseconds(5)])
    let appState = AppState()
    let viewModel = SongLibraryViewModel(
        appState: appState,
        practicePreparationService: service,
        indexStore: PreparationTestIndexStore(),
        fileStore: PreparationTestFileStore(),
        audioImportService: PreparationTestAudioImporter(),
        paths: SongLibraryPaths(),
        bundledProvider: PreparationTestBundledProvider(entries: entries, scoreURL: url),
        audioPlayer: PreparationTestAudioPlayer(),
        practiceProgressRepository: PreparationTestProgressRepository()
    )

    async let oldResult = viewModel.preparePractice(entryID: firstID)
    try await Task.sleep(for: .milliseconds(10))
    let newResult = await viewModel.preparePractice(entryID: secondID)
    let staleResult = await oldResult

    #expect(newResult)
    #expect(staleResult == false)
    #expect(appState.practiceSetupState.preparedPracticeIdentity?.songID == secondID)
}

private final class PreparationTestIndexStore: SongLibraryIndexStoreProtocol {
    var value = SongLibraryIndex.empty
    func load() throws -> SongLibraryIndex { value }
    func save(_ index: SongLibraryIndex) throws { value = index }
}

private struct PreparationTestFileStore: SongFileStoreProtocol {
    func importMusicXML(from _: URL) throws -> ImportedSongScoreFile { throw CocoaError(.fileNoSuchFile) }
    func scoreFileURL(fileName _: String) throws -> URL { throw CocoaError(.fileNoSuchFile) }
    func audioFileURL(fileName _: String) throws -> URL { throw CocoaError(.fileNoSuchFile) }
    func deleteScoreFile(named _: String) throws {}
    func deleteAudioFile(named _: String) throws {}
}

private struct PreparationTestAudioImporter: AudioImportServiceProtocol {
    func importAudio(from _: URL) throws -> String { throw CocoaError(.fileNoSuchFile) }
}

private final class PreparationTestAudioPlayer: SongAudioPlayerProtocol {
    var onPlaybackFinished: ((UUID?) -> Void)?
    var currentEntryID: UUID?
    func play(entryID _: UUID, url _: URL) throws {}
    func pause() {}
    func stop() {}
    func isPlaying(entryID _: UUID) -> Bool { false }
}


private actor PreparationTestProgressRepository: PracticeProgressRepositoryProtocol {
    func load() -> PracticeProgressLoadResult { .loaded(PracticeProgressDocument()) }
    func progress(for _: PracticeSongIdentity) -> SongPracticeProgress? { nil }
    func upsert(_: SongPracticeProgress) {}
    func remove(songID _: UUID) {}
}
