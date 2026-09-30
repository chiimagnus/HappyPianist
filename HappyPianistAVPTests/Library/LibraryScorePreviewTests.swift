import Diagnostics
import CoreGraphics
import Foundation
import Library
import MusicXML
import Notation
import Practice
import Testing
@testable import HappyPianistAVP

@Test
@MainActor
func selectedFolioOpensWrittenScoreWithoutPlaybackOrPracticeWrites() async throws {
    let first = previewEntry("First")
    let second = previewEntry("Second")
    let preparation = PreviewPreparation()
    let repository = PreviewHistoryRepository()
    let preview = makePreview(entries: [first, second], preparation: preparation)
    let library = SongLibraryViewModelTestHarness.make(index: SongLibraryIndex(entries: [first, second], lastSelectedEntryID: first.id), practiceProgressRepository: repository, scorePreview: preview)
    await TestAsyncWait.until("one history snapshot") { library.practiceSnapshotState == .invitation(previewIdentity(first)) }
    let historyRequests = await repository.historyRequests
    library.confirmFolio(second.id)
    #expect(library.selectedEntryID == second.id)
    #expect(!preview.isOpen)
    await TestAsyncWait.until("selected history snapshot") { library.practiceSnapshotState == .invitation(previewIdentity(second)) }
    let selectedRequests = await repository.historyRequests
    library.confirmFolio(second.id)
    await ready(preview)
    let plan = try #require(preview.pageOwner.plan)
    #expect(plan.input.identity.songID == second.id)
    #expect(plan.input.projection == preview.prepared?.notationProjection)
    #expect(plan.input.measureSpans == preview.prepared?.measureSpans)
    #expect(library.currentListeningEntryID == nil)
    #expect(await preparation.options == [.practice])
    #expect(await preparation.files.first?.fileName == second.displayName)
    #expect(await preparation.files.first?.importedAt == second.importedAt)
    #expect(await preparation.files.first?.storedURL.lastPathComponent == second.musicXMLFileName)
    await library.didTapListen(entryID: second.id)
    #expect(library.isListeningPlaying(entryID: second.id))
    preview.close()
    #expect(library.selectedEntryID == second.id)
    #expect(preview.prepared == nil && preview.pageOwner.plan == nil)
    library.openSelectedScore()
    await ready(preview)
    #expect(library.isListeningPlaying(entryID: second.id))
    #expect(await preparation.requests.count == 2)
    #expect(await repository.writes == 0)
    #expect(await repository.historyRequests == selectedRequests)
    #expect(historyRequests == 1)
    library.index.entries[1].scoreFileVersionID = UUID()
    #expect(!preview.isOpen && preview.prepared == nil && preview.pageOwner.plan == nil)
    preview.close()
    #expect(library.isListeningPlaying(entryID: second.id))
    library.stopListening()
}

@Test
@MainActor
func resolvedNewFileVersionIsRejectedBeforePreparation() async throws {
    let entry = previewEntry("Old")
    var replacement = entry
    replacement.scoreFileVersionID = UUID()
    let preparation = PreviewPreparation()
    let preview = makePreview(entries: [replacement], preparation: preparation)
    preview.open(previewIdentity(entry), isCurrent: { true })
    await TestAsyncWait.until("version rejected") { !preview.isOpen }
    #expect(await preparation.requests.isEmpty)
    #expect(preview.prepared == nil && preview.pageOwner.plan == nil)
}

@Test(arguments: ["close", "select", "importPicker", "importTransaction", "delete", "version"])
@MainActor
func previewInvalidationRejectsLatePreparation(action: String) async throws {
    let first = previewEntry("First")
    let second = previewEntry("Second")
    let preparation = PreviewPreparation(held: true)
    let preview = makePreview(entries: [first, second], preparation: preparation)
    let library = SongLibraryViewModelTestHarness.make(index: SongLibraryIndex(entries: [first, second], lastSelectedEntryID: first.id), scorePreview: preview)
    library.openSelectedScore()
    await TestAsyncWait.until("held preparation") { await preparation.isHeld }
    switch action {
    case "close": preview.close()
    case "select": library.selectEntry(second.id)
    case "importPicker": library.didTapImportMusicXML()
    case "importTransaction": await library.importMusicXML(from: [URL(fileURLWithPath: "/tmp/new.musicxml")])
    case "delete": await library.deleteEntry(entryID: first.id)
    default:
        library.index.entries[0].scoreFileVersionID = UUID()
    }
    await preparation.release()
    await TestAsyncWait.until("invalidated preview") { !preview.isOpen }
    #expect(preview.prepared == nil && preview.pageOwner.plan == nil)
    #expect(library.currentListeningEntryID == nil)
}

@Test(arguments: [false, true])
@MainActor
func rapidPreviewReplacementCannotPublishOlderScore(olderFails: Bool) async throws {
    let first = previewEntry("First")
    let second = previewEntry("Second")
    let preparation = PreviewPreparation(held: true, failFirst: olderFails)
    let preview = makePreview(entries: [first, second], preparation: preparation)
    preview.open(previewIdentity(first), isCurrent: { true })
    await TestAsyncWait.until("first held request") { await preparation.isHeld }
    preview.open(previewIdentity(second), isCurrent: { true })
    await ready(preview)
    #expect(preview.pageOwner.plan?.input.identity.songID == second.id)
    await preparation.release()
    await TestAsyncWait.until("older preparation returned") { await preparation.returnedCount == 2 }
    #expect(preview.identity == previewIdentity(second))
    #expect(preview.pageOwner.plan?.input.identity.songID == second.id)
    preview.close()
}

@Test
@MainActor
func previewClosedDuringResolutionDoesNotPrepareReturnedFile() async throws {
    let entry = previewEntry("Resolution")
    let resolver = HeldPreviewResolver(entry: entry)
    let preparation = PreviewPreparation()
    let preview = LibraryScorePreviewViewModel(resolver: resolver, preparationService: preparation, diagnosticsReporter: PreviewDiagnostics())
    preview.open(previewIdentity(entry), isCurrent: { true })
    await TestAsyncWait.until("held resolver") { await resolver.isHeld }
    preview.close()
    await resolver.release()
    await TestAsyncWait.until("resolver returned") { await resolver.returned }
    #expect(await preparation.requests.isEmpty)
    #expect(!preview.isOpen && preview.pageOwner.plan == nil)
}

@Test
@MainActor
func failedPreviewCanRetryWithoutRetainingPreparedScore() async throws {
    let entry = previewEntry("Retry")
    let preparation = PreviewPreparation(failFirst: true)
    let diagnostics = PreviewDiagnostics()
    let preview = makePreview(entries: [entry], preparation: preparation, diagnostics: diagnostics)
    preview.open(previewIdentity(entry), isCurrent: { true })
    await TestAsyncWait.until("preview failed") { if case .failure = preview.state { return true }; return false }
    #expect(preview.prepared == nil && preview.pageOwner.plan == nil)
    await TestAsyncWait.until("safe failure diagnostic") { await !diagnostics.events.isEmpty }
    #expect(await diagnostics.events.allSatisfy { !$0.reason.contains("/Users/") && !$0.reason.contains("<score-partwise>") })
    preview.open(previewIdentity(entry), isCurrent: { true })
    await ready(preview)
    #expect(await preparation.requests.count == 2)
    preview.close()
}

@Test(arguments: [false, true])
@MainActor
func libraryConfirmedRecoveryPreservesActualBackupAndRejectsStaleConfirmation(replacementFails: Bool) async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let paths = PracticeProgressPaths(rootDirectoryURL: directory)
    let original = Data("corrupted history".utf8)
    try original.write(to: paths.fileURL)
    let repository = replacementFails
        ? FilePracticeProgressRepository(paths: paths, replaceFile: { _, _, _, _ in throw CocoaError(.fileWriteUnknown) })
        : FilePracticeProgressRepository(paths: paths)
    let entry = previewEntry("Recovery")
    let library = SongLibraryViewModelTestHarness.make(index: SongLibraryIndex(entries: [entry], lastSelectedEntryID: entry.id), practiceProgressRepository: repository, practiceProgressRecovery: repository)
    await TestAsyncWait.until("corrupted snapshot") { if case .unavailable = library.practiceSnapshotState { return true }; return false }
    #expect(try Data(contentsOf: paths.fileURL) == original)
    await library.recoverCorruptedSelectedPracticeHistory(expectedIdentity: previewIdentity(previewEntry("Stale")))
    #expect(try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) == [paths.fileURL])
    await library.recoverCorruptedSelectedPracticeHistory(expectedIdentity: previewIdentity(entry))
    if replacementFails {
        #expect(try Data(contentsOf: paths.fileURL) == original)
        #expect(try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) == [paths.fileURL])
        if case .corrupted = await repository.history(for: entry.id) {} else { Issue.record("Original corrupted file must remain") }
        if case let .unavailable(unavailable) = library.practiceSnapshotState { #expect(unavailable.reason == .corrupted) }
        else { Issue.record("Backup failure must not publish empty history") }
    } else {
        await TestAsyncWait.until("new history snapshot") { library.practiceSnapshotState == .invitation(previewIdentity(entry)) }
        #expect(await repository.load() == .loaded(PracticeProgressDocument()))
        let backup = try #require(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first { $0 != paths.fileURL })
        #expect(try Data(contentsOf: backup) == original)
    }
}

@Test
@MainActor
func previewAnnotationsRequireExactSelectionAndRevisionAndIncludeRests() async throws {
    let entry = previewEntry("Annotations")
    let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).musicxml")
    defer { try? FileManager.default.removeItem(at: url) }
    let xml = """
    <score-partwise version="4.0"><part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list><part id="P1">
    <measure number="1"><attributes><divisions>1</divisions><staves>2</staves><time><beats>4</beats><beat-type>4</beat-type></time></attributes><note><pitch><step>C</step><octave>5</octave></pitch><duration>4</duration><type>whole</type><staff>1</staff></note></measure>
    <measure number="2"><note><rest measure="yes"/><duration>4</duration><type>whole</type><staff>1</staff></note></measure>
    </part></score-partwise>
    """
    try Data(xml.utf8).write(to: url)
    let prepared = try await PracticePreparationService(diagnosticsReporter: PreviewDiagnostics()).prepare(songID: entry.id, from: url, file: ImportedMusicXMLFile(fileName: entry.displayName, storedURL: url, importedAt: entry.importedAt), options: .practice)
    let owner = GrandStaffNotationPageViewModel()
    await owner.load(.init(identity: prepared.identity, projection: prepared.notationProjection, measureSpans: prepared.measureSpans, facts: .init(logicalInstrument: prepared.scoreContext.logicalInstrument, structuralPartID: prepared.scoreContext.structuralPartID), attributeTimeline: prepared.attributeTimeline))
    let plan = try #require(owner.plan)
    let first = try #require(prepared.measureSpans.first)
    let rest = try #require(prepared.measureSpans.last)
    func overview(revision: String?, states: [PracticeSourceMeasureID: SongPracticeSourceMeasureState]) -> SongPracticeLibraryOverview {
        .init(identity: previewIdentity(entry), status: .learning, sessionSummary: .init(latestPracticeEndedAt: nil, totalActiveDurationMilliseconds: 1000, sessionCount: 1, streak: nil), measureProgress: .available(.init(stableSourceMeasureCount: 1, learningSourceMeasureCount: 1, unpracticedSourceMeasureCount: 0)), scoreRevision: revision, sourceMeasureStates: states, resumeSourceMeasureID: rest.sourceMeasureID, focusMeasures: [.init(sourceMeasureID: rest.sourceMeasureID, reason: .learning)])
    }
    let annotations = LibraryScorePreviewViewModel.annotations(overview: overview(revision: prepared.identity.scoreRevision, states: [first.sourceMeasureID: .stable, rest.sourceMeasureID: .learning]), plan: plan, selection: previewIdentity(entry))
    #expect(annotations.count == 2)
    #expect(annotations.first?.state == .stable)
    #expect(annotations.last?.state == .learning)
    #expect(annotations.last?.isResume == true && annotations.last?.isFocus == true)
    #expect(plan.pages.flatMap(\.measures).contains { $0.span.occurrenceID == rest.occurrenceID && $0.rect.width > 0 })
    #expect(LibraryScorePreviewViewModel.annotations(overview: overview(revision: nil, states: [:]), plan: plan, selection: previewIdentity(entry)).isEmpty)
    #expect(LibraryScorePreviewViewModel.annotations(overview: overview(revision: "outdated", states: [:]), plan: plan, selection: previewIdentity(entry)).isEmpty)
    #expect(LibraryScorePreviewViewModel.annotations(overview: overview(revision: prepared.identity.scoreRevision, states: [:]), plan: plan, selection: previewIdentity(previewEntry("Another"))).isEmpty)
    #expect(LibraryScorePreviewViewModel.annotations(overview: overview(revision: prepared.identity.scoreRevision, states: [:]), plan: plan, selection: previewIdentity(entry)).allSatisfy { $0.state == .unpracticed })
    #expect(owner.plan == plan)
}

@MainActor
private func ready(_ preview: LibraryScorePreviewViewModel) async {
    await TestAsyncWait.until("ready score preview") { if case .ready = preview.state { return true }; return false }
}

private func previewEntry(_ name: String) -> SongLibraryEntry {
    SongLibraryEntry(id: UUID(), displayName: name, musicXMLFileName: "\(name).musicxml", scoreFileVersionID: UUID(), importedAt: Date(timeIntervalSince1970: 1000), audioFileName: "\(name).mp3", isBundled: false)
}

private func previewIdentity(_ entry: SongLibraryEntry) -> SongPracticeLibrarySelectionIdentity {
    .init(songID: entry.id, scoreFileVersionID: entry.scoreFileVersionID)
}

@MainActor
private func makePreview(entries: [SongLibraryEntry], preparation: PreviewPreparation, diagnostics: PreviewDiagnostics = PreviewDiagnostics()) -> LibraryScorePreviewViewModel {
    LibraryScorePreviewViewModel(resolver: PreviewResolver(entries: entries), preparationService: preparation, diagnosticsReporter: diagnostics)
}

private struct PreviewResolver: SongLibraryEntryResolving {
    let entries: [SongLibraryEntry]
    func resolve(songID: UUID) async -> Result<ResolvedSongLibraryEntry, SongLibraryEntryResolutionError> {
        guard let entry = entries.first(where: { $0.id == songID }) else { return .failure(.init(preparationError: .scoreFileNotFound, diagnosticFileReference: nil)) }
        return .success(.init(entry: entry, scoreURL: URL(fileURLWithPath: "/tmp/\(entry.musicXMLFileName)"), diagnosticFileReference: nil))
    }
}

private actor HeldPreviewResolver: SongLibraryEntryResolving {
    let entry: SongLibraryEntry
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var returned = false
    var isHeld: Bool { continuation != nil }
    init(entry: SongLibraryEntry) { self.entry = entry }
    func resolve(songID: UUID) async -> Result<ResolvedSongLibraryEntry, SongLibraryEntryResolutionError> {
        await withCheckedContinuation { continuation = $0 }
        returned = true
        return await PreviewResolver(entries: [entry]).resolve(songID: songID)
    }
    func release() { continuation?.resume(); continuation = nil }
}

private actor PreviewPreparation: PracticePreparationServiceProtocol {
    private var continuation: CheckedContinuation<Void, Never>?
    private let held: Bool
    private let failFirst: Bool
    private(set) var requests: [UUID] = []
    private(set) var options: [PracticePreparationOptions] = []
    private(set) var files: [ImportedMusicXMLFile] = []
    private(set) var returnedCount = 0
    var isHeld: Bool { continuation != nil }

    init(held: Bool = false, failFirst: Bool = false) { self.held = held; self.failFirst = failFirst }

    func prepare(songID: UUID, from: URL, file: ImportedMusicXMLFile, options: PracticePreparationOptions) async throws -> PreparedPractice {
        requests.append(songID)
        self.options.append(options)
        files.append(file)
        let first = requests.count == 1
        if first && held { await withCheckedContinuation { continuation = $0 } }
        returnedCount += 1
        if first && failFirst { throw PracticePreparationError.xmlParseFailed(line: 1, column: 1, reason: "/Users/private/<score-partwise>") }
        return makeTestPreparedPractice(identity: PracticeSongIdentity(songID: songID, scoreRevision: "preview-test"), file: file)
    }
    func release() { continuation?.resume(); continuation = nil }
}

private actor PreviewDiagnostics: DiagnosticsReporting {
    private(set) var events: [DiagnosticEvent] = []
    func record(_ event: DiagnosticEvent) -> DiagnosticRecordResult {
        events.append(event)
        return .init(persistedForExport: false)
    }
}

private actor PreviewHistoryRepository: PracticeProgressRepositoryProtocol {
    private(set) var historyRequests = 0
    private(set) var writes = 0
    func load() -> PracticeProgressLoadResult { .loaded(PracticeProgressDocument()) }
    func progress(for: PracticeSongIdentity) -> SongPracticeProgress? { nil }
    func history(for songID: UUID) -> PracticeSongHistoryLoadResult {
        historyRequests += 1
        return .loaded(PracticeSongHistory(songID: songID, progresses: [], scoreMetadata: [], sessions: []))
    }
    func upsert(_: SongPracticeProgress) { writes += 1 }
    func upsert(_: SongScorePracticeMetadata) { writes += 1 }
    func remove(songID: UUID) { writes += 1 }
}
