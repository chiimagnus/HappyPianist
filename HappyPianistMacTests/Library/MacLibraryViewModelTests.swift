import Diagnostics
import Foundation
import HappyPianistTestFixtures
import Library
import Practice
import Synchronization
@testable import HappyPianistMac
import Testing

@MainActor
struct MacLibraryViewModelTests {
    @Test func importsOnlyALocalCopyAndReleasesTheSecurityScope() async throws {
        let fixture = try MacLibraryFixture()
        defer { fixture.remove() }
        let sourceURL = try fixture.copyFixture(named: "PracticeLearningLoopEightMeasures.musicxml")

        let stageResult = await fixture.service.stageImports(from: [sourceURL])
        let stagedImport = try #require(stageResult.items.first?.stagedImport)
        let journalData = try Data(contentsOf: fixture.paths.transactionJournalFileURL(operationID: stagedImport.id))
        #expect(fixture.containsExternalReference(journalData) == false)

        let processResult = await fixture.service.process(operationID: stagedImport.id)
        guard case let .committed(_, entry) = processResult else {
            Issue.record("Expected a committed import")
            return
        }

        let indexData = try Data(contentsOf: fixture.paths.indexFileURL())
        let copiedScoreData = try Data(contentsOf: fixture.paths.scoreFileURL(safeFileName: entry.musicXMLFileName))
        let sourceData = try Data(contentsOf: sourceURL)
        #expect(fixture.containsExternalReference(indexData) == false)
        #expect(copiedScoreData == sourceData)
        #expect(FileManager.default.fileExists(atPath: fixture.progressPaths.fileURL.path(percentEncoded: false)) == false)
        #expect(fixture.scope.accessedURLs == [sourceURL])
        #expect(fixture.scope.releasedURLs == [sourceURL])
    }

    @Test func recoversBeforeLoadingThenImportsAndPersistsTheSelectedEntry() async throws {
        let fixture = try MacLibraryFixture()
        defer { fixture.remove() }
        await fixture.viewModel.loadLibrary()
        #expect(fixture.viewModel.loadState == .ready)
        #expect(fixture.viewModel.entries.isEmpty)

        await fixture.viewModel.importMusicXML(from: [
            try fixture.copyFixture(named: "PracticeLearningLoopEightMeasures.musicxml"),
        ])

        #expect(fixture.viewModel.importState == .idle)
        let selectedEntryID = try #require(fixture.viewModel.selectedEntryID)
        #expect(fixture.viewModel.entries.map(\.id) == [selectedEntryID])
        #expect(try await fixture.indexStore.load().lastSelectedEntryID == selectedEntryID)
    }

    @Test func preservesABlockedRecoveryAsAUserAction() async throws {
        let fixture = try MacLibraryFixture(importTransactionService: BlockedImportTransactionService())
        defer { fixture.remove() }

        await fixture.viewModel.loadLibrary()

        #expect(fixture.viewModel.loadState == .recoveryBlocked("恢复事务尚未收敛。"))
    }

    @Test func bindsReplacesPreviewsAndDeletesUserAudioWithoutExternalReferences() async throws {
        let fixture = try MacLibraryFixture()
        defer { fixture.remove() }
        await fixture.viewModel.loadLibrary()
        await fixture.viewModel.importMusicXML(from: [
            try fixture.copyFixture(named: "PracticeLearningLoopEightMeasures.musicxml"),
        ])
        let entryID = try #require(fixture.viewModel.selectedEntryID)
        let firstAudioURL = try fixture.writeExternalAudio(named: "first.mp3", contents: "first")

        await fixture.viewModel.bindAudio(entryID: entryID, from: firstAudioURL)

        let firstAudioFileName = try #require(
            fixture.viewModel.entries.first(where: { $0.id == entryID })?.audioFileName
        )
        let firstStoredAudioURL = try await fixture.fileStore.audioFileURL(fileName: firstAudioFileName)
        #expect(FileManager.default.fileExists(atPath: firstStoredAudioURL.path(percentEncoded: false)))
        #expect(try await fixture.indexStore.load().entries.first?.audioFileName == firstAudioFileName)
        #expect(fixture.containsExternalReference(try Data(contentsOf: fixture.paths.indexFileURL())) == false)

        await fixture.viewModel.toggleListening(entryID: entryID)
        #expect(fixture.audioPlayer.playedEntryIDs == [entryID])

        let replacementAudioURL = try fixture.writeExternalAudio(named: "replacement.m4a", contents: "replacement")
        await fixture.viewModel.bindAudio(entryID: entryID, from: replacementAudioURL)

        let replacementAudioFileName = try #require(
            fixture.viewModel.entries.first(where: { $0.id == entryID })?.audioFileName
        )
        #expect(replacementAudioFileName != firstAudioFileName)
        #expect(FileManager.default.fileExists(atPath: firstStoredAudioURL.path(percentEncoded: false)) == false)

        let scoreFileName = try #require(
            fixture.viewModel.entries.first(where: { $0.id == entryID })?.musicXMLFileName
        )
        let replacementStoredAudioURL = try await fixture.fileStore.audioFileURL(
            fileName: replacementAudioFileName
        )
        await fixture.viewModel.deleteEntry(entryID: entryID)

        #expect(fixture.viewModel.entries.isEmpty)
        #expect(FileManager.default.fileExists(atPath: replacementStoredAudioURL.path(percentEncoded: false)) == false)
        #expect(
            FileManager.default.fileExists(
                atPath: try fixture.paths.scoreFileURL(safeFileName: scoreFileName).path(percentEncoded: false)
            ) == false
        )
    }

    @Test func staleAudioResolutionCannotStartPlaybackAfterSelectionChanges() async throws {
        let fixture = try MacLibraryFixture()
        defer { fixture.remove() }
        let first = fixture.makeAudioEntry(name: "first")
        let second = fixture.makeAudioEntry(name: "second")
        _ = try await fixture.indexStore.appendUserEntry(first)
        _ = try await fixture.indexStore.appendUserEntry(second)
        let fileStore = ControlledListeningFileStore()
        let player = MacLibraryAudioPlayer()
        let viewModel = MacLibraryViewModel(
            indexStore: fixture.indexStore,
            importTransactionService: fixture.service,
            fileStore: fileStore,
            audioImportService: fixture.audioImportService,
            bundledProvider: EmptyMacLibraryProvider(),
            audioPlayer: player,
            progressRepository: fixture.progressRepository,
            diagnosticsReporter: MacLibraryDiagnosticsReporter()
        )
        await viewModel.loadLibrary()

        let listenTask = Task { @MainActor in
            await viewModel.toggleListening(entryID: first.id)
        }
        await fileStore.waitForRequestCount(1)
        await viewModel.selectEntry(second.id)
        await fileStore.succeedRequest(at: 0)
        await listenTask.value

        #expect(viewModel.selectedEntryID == second.id)
        #expect(player.playedEntryIDs.isEmpty)
    }

    @Test func exposesListeningProgressAndSeeksTheCurrentEntry() async throws {
        let fixture = try MacLibraryFixture()
        defer { fixture.remove() }
        let entry = fixture.makeAudioEntry(name: "seekable")
        _ = try await fixture.indexStore.appendUserEntry(entry)
        await fixture.viewModel.loadLibrary()

        await fixture.viewModel.toggleListening(entryID: entry.id)
        fixture.viewModel.seekListening(entryID: entry.id, progress: 0.25)

        #expect(fixture.viewModel.listeningDuration == 12)
        #expect(fixture.viewModel.listeningCurrentTime == 3)
        #expect(fixture.audioPlayer.currentTime == 3)
    }
}

private struct MacLibraryFixture {
    let rootURL: URL
    let documentsURL: URL
    let externalURL: URL
    let paths: SongLibraryPaths
    let progressPaths: PracticeProgressPaths
    let indexStore: SongLibraryIndexStore
    let service: SongLibraryImportTransactionService
    let fileStore: SongFileStore
    let audioImportService: AudioImportService
    let progressRepository: FilePracticeProgressRepository
    let audioPlayer: MacLibraryAudioPlayer
    let viewModel: MacLibraryViewModel
    let scope: MacSecurityScopeSpy

    @MainActor
    init(importTransactionService: (any SongLibraryImportTransactionServicing)? = nil) throws {
        rootURL = FileManager.default.temporaryDirectory.appending(
            path: "HappyPianistMacLibraryTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        documentsURL = rootURL.appending(path: "Documents", directoryHint: .isDirectory)
        externalURL = rootURL.appending(path: "External", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: documentsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: externalURL, withIntermediateDirectories: true)

        paths = SongLibraryPaths(
            fileManager: MacLibraryDocumentsFileManager(documentsURL: documentsURL)
        )
        progressPaths = PracticeProgressPaths(
            rootDirectoryURL: rootURL.appending(path: "PracticeProgress", directoryHint: .isDirectory)
        )
        indexStore = SongLibraryIndexStore(
            fileManager: MacLibraryDocumentsFileManager(documentsURL: documentsURL),
            paths: SongLibraryPaths(
                fileManager: MacLibraryDocumentsFileManager(documentsURL: documentsURL)
            )
        )
        scope = MacSecurityScopeSpy()
        service = SongLibraryImportTransactionService(
            indexStore: indexStore,
            paths: SongLibraryPaths(
                fileManager: MacLibraryDocumentsFileManager(documentsURL: documentsURL)
            ),
            fileManager: MacLibraryDocumentsFileManager(documentsURL: documentsURL),
            diagnostics: MacLibraryDiagnosticsReporter(),
            securityScopedResourceAccessor: scope
        )
        let fileStoreFileManager = MacLibraryDocumentsFileManager(documentsURL: documentsURL)
        fileStore = SongFileStore(
            fileManager: fileStoreFileManager,
            paths: SongLibraryPaths(
                fileManager: MacLibraryDocumentsFileManager(documentsURL: documentsURL)
            )
        )
        let audioImportFileManager = MacLibraryDocumentsFileManager(documentsURL: documentsURL)
        audioImportService = AudioImportService(
            fileManager: audioImportFileManager,
            paths: SongLibraryPaths(
                fileManager: MacLibraryDocumentsFileManager(documentsURL: documentsURL)
            )
        )
        progressRepository = FilePracticeProgressRepository(paths: progressPaths)
        audioPlayer = MacLibraryAudioPlayer()
        viewModel = MacLibraryViewModel(
            indexStore: indexStore,
            importTransactionService: importTransactionService ?? service,
            fileStore: fileStore,
            audioImportService: audioImportService,
            bundledProvider: EmptyMacLibraryProvider(),
            audioPlayer: audioPlayer,
            progressRepository: progressRepository,
            diagnosticsReporter: MacLibraryDiagnosticsReporter()
        )
    }

    func copyFixture(named name: String) throws -> URL {
        let destination = externalURL.appending(path: name)
        try FileManager.default.copyItem(at: HappyPianistTestFixtures.url(named: name), to: destination)
        return destination
    }

    func containsExternalReference(_ data: Data) -> Bool {
        String(data: data, encoding: .utf8)?.contains(externalURL.path(percentEncoded: false)) == true
    }

    func writeExternalAudio(named name: String, contents: String) throws -> URL {
        let url = externalURL.appending(path: name)
        try Data(contents.utf8).write(to: url)
        return url
    }

    func makeAudioEntry(name: String) -> SongLibraryEntry {
        SongLibraryEntry(
            id: UUID(),
            displayName: name,
            musicXMLFileName: "\(name).musicxml",
            scoreFileVersionID: UUID(),
            importedAt: .distantPast,
            audioFileName: "\(name).mp3"
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

private final class MacLibraryDocumentsFileManager: FileManager {
    private let documentsURL: URL

    init(documentsURL: URL) {
        self.documentsURL = documentsURL
        super.init()
    }

    override func urls(for directory: SearchPathDirectory, in domainMask: SearchPathDomainMask) -> [URL] {
        directory == .documentDirectory ? [documentsURL] : super.urls(for: directory, in: domainMask)
    }
}

private final class MacSecurityScopeSpy: SecurityScopedResourceAccessing {
    private let state = Mutex((accessedURLs: [URL](), releasedURLs: [URL]()))

    var accessedURLs: [URL] {
        state.withLock { $0.accessedURLs }
    }

    var releasedURLs: [URL] {
        state.withLock { $0.releasedURLs }
    }

    func startAccessing(_ url: URL) -> Bool {
        state.withLock { $0.accessedURLs.append(url) }
        return true
    }

    func stopAccessing(_ url: URL) {
        state.withLock { $0.releasedURLs.append(url) }
    }
}

private struct EmptyMacLibraryProvider: BundledSongLibraryProviderProtocol {
    func bundledEntries() -> [SongLibraryEntry] { [] }
    func musicXMLURL(fileName _: String) -> URL? { nil }
    func audioURL(fileName _: String) -> URL? { nil }
}

private actor MacLibraryDiagnosticsReporter: DiagnosticsReporting {
    func record(_: DiagnosticEvent) -> DiagnosticRecordResult {
        DiagnosticRecordResult(persistedForExport: false)
    }
}

@MainActor
private final class MacLibraryAudioPlayer: SongAudioPlayerProtocol {
    var onPlaybackFinished: ((UUID?) -> Void)?
    private(set) var currentEntryID: UUID?
    private(set) var playedEntryIDs: [UUID] = []
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 12

    func play(entryID: UUID, url _: URL) throws {
        currentEntryID = entryID
        playedEntryIDs.append(entryID)
    }

    func pause() {}

    func stop() {
        currentEntryID = nil
    }

    func seek(to time: TimeInterval) {
        currentTime = min(max(time, 0), duration)
    }

    func isPlaying(entryID: UUID) -> Bool {
        currentEntryID == entryID
    }
}

private actor ControlledListeningFileStore: SongFileStoreProtocol {
    private var requests: [CheckedContinuation<URL, Error>?] = []

    func scoreFileURL(fileName _: String) async throws -> URL {
        throw CocoaError(.fileNoSuchFile)
    }

    func audioFileURL(fileName _: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            requests.append(continuation)
        }
    }

    func waitForRequestCount(_ count: Int) async {
        while requests.count < count {
            await Task.yield()
        }
    }

    func succeedRequest(at index: Int) {
        guard requests.indices.contains(index), let request = requests[index] else { return }
        requests[index] = nil
        request.resume(returning: URL(fileURLWithPath: "/tmp/audio.mp3"))
    }

    func deleteScoreFile(named _: String) async throws {}
    func deleteAudioFile(named _: String) async throws {}
}

private actor BlockedImportTransactionService: SongLibraryImportTransactionServicing {
    func recoverPendingTransactions() -> SongLibraryTransactionRecoveryResult {
        .blocked(SongLibraryBlockedImport(operationID: nil, message: "恢复事务尚未收敛。"))
    }

    func stageImports(from _: [URL]) -> SongLibraryImportBatchStageResult {
        SongLibraryImportBatchStageResult(items: [], blocked: nil)
    }

    func process(operationID _: UUID) -> SongLibraryImportProcessResult {
        .blocked(SongLibraryBlockedImport(operationID: nil, message: "恢复事务尚未收敛。"))
    }

    func confirm(operationID _: UUID) -> SongLibraryImportProcessResult {
        .blocked(SongLibraryBlockedImport(operationID: nil, message: "恢复事务尚未收敛。"))
    }

    func cancel(operationID _: UUID) -> Bool { false }
}

private extension SongLibraryImportBatchItem {
    var stagedImport: SongLibraryStagedImport? {
        guard case let .staged(stagedImport) = self else { return nil }
        return stagedImport
    }
}
