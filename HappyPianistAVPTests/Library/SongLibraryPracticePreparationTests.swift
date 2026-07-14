import Foundation
@testable import HappyPianistAVP
import Testing

private actor DelayedPreparationService: PracticePreparationServiceProtocol {
    let delays: [UUID: Duration]
    let includesMeasureSpans: Bool
    private var requestedSongIDs: [UUID] = []

    init(delays: [UUID: Duration], includesMeasureSpans: Bool = true) {
        self.delays = delays
        self.includesMeasureSpans = includesMeasureSpans
    }

    func prepare(songID: UUID, from _: URL, file: ImportedMusicXMLFile) async throws -> PreparedPractice {
        requestedSongIDs.append(songID)
        if let delay = delays[songID] {
            try await Task.sleep(for: delay)
        }
        return PreparedPractice(
            identity: PracticeSongIdentity(songID: songID, scoreRevision: songID.uuidString),
            steps: [
                PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1)]),
                PracticeStep(tick: 480, notes: [PracticeStepNote(midiNote: 62, staff: 1)]),
            ],
            file: file,
            tempoMap: MusicXMLTempoMap(tempoEvents: []),
            pedalTimeline: nil,
            fermataTimeline: nil,
            attributeTimeline: nil,
            highlightGuides: [],
            measureSpans: includesMeasureSpans ? [
                MusicXMLMeasureSpan(
                    partID: "P1",
                    measureNumber: 1,
                    sourceMeasureIndex: 0,
                    sourceMeasureNumberToken: "1",
                    occurrenceIndex: 0,
                    startTick: 0,
                    endTick: 480
                ),
                MusicXMLMeasureSpan(
                    partID: "P1",
                    measureNumber: 2,
                    sourceMeasureIndex: 1,
                    sourceMeasureNumberToken: "2",
                    occurrenceIndex: 1,
                    startTick: 480,
                    endTick: 960
                ),
            ] : [],
            unsupportedNoteCount: 0
        )
    }

    func requests() -> [UUID] {
        requestedSongIDs
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
    let guide = ARGuideViewModel(
        appState: appState,
        practiceSetupState: appState.practiceSetupState
    )
    let viewModel = SongLibraryViewModel(
        arGuideViewModel: guide,
        practicePreparationService: service,
        indexStore: PreparationTestIndexStore(),
        fileStore: PreparationTestFileStore(),
        audioImportService: PreparationTestAudioImporter(),
        bundledProvider: PreparationTestBundledProvider(entries: entries, scoreURL: url),
        audioPlayer: PreparationTestAudioPlayer(),
        practiceProgressRepository: PreparationTestProgressRepository(),
        diagnosticsReporter: InMemoryDiagnosticsReporter(),
        initialSnapshot: .loaded(index: .empty, bundledEntries: entries),
        selectionSettleDelay: .zero
    )

    viewModel.selectEntryForPractice(firstID)
    try await Task.sleep(for: .milliseconds(10))
    viewModel.selectEntryForPractice(secondID)
    try await waitForPreparation(viewModel, entryID: secondID)

    #expect(viewModel.practicePreparationState == .ready(
        entryID: secondID,
        identity: PracticeSongIdentity(songID: secondID, scoreRevision: secondID.uuidString)
    ))
    #expect(appState.practiceSetupState.preparedPracticeIdentity?.songID == secondID)
}

@Test
@MainActor
func rapidSelectionOnlyPersistsAndPreparesTheSettledEntry() async throws {
    let url = FileManager.default.temporaryDirectory.appending(
        path: "settled-selection-\(UUID().uuidString).musicxml"
    )
    try Data("<score-partwise/>".utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let entries = ["First", "Second", "Third"].map { name in
        SongLibraryEntry(
            id: UUID(),
            displayName: name,
            musicXMLFileName: "\(name).musicxml",
            importedAt: .now,
            audioFileName: nil,
            isBundled: true
        )
    }
    let service = DelayedPreparationService(delays: [:])
    let indexStore = PreparationTestIndexStore()
    let viewModel = makeSelectionViewModel(
        entries: entries,
        scoreURL: url,
        service: service,
        indexStore: indexStore,
        settleDelay: .milliseconds(40)
    )

    viewModel.selectEntryForPractice(entries[0].id)
    await Task.yield()
    viewModel.selectEntryForPractice(entries[1].id)
    await Task.yield()
    viewModel.selectEntryForPractice(entries[2].id)
    try await waitForPreparation(viewModel, entryID: entries[2].id)

    let savedEntryIDs = await indexStore.savedEntryIDs
    let preparedEntryIDs = await service.requests()
    #expect(savedEntryIDs == [entries[2].id])
    #expect(preparedEntryIDs == [entries[2].id])
}

@Test
@MainActor
func selectionPersistenceFailureDoesNotBlockPreparation() async throws {
    let url = FileManager.default.temporaryDirectory.appending(
        path: "failed-selection-save-\(UUID().uuidString).musicxml"
    )
    try Data("<score-partwise/>".utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let entry = SongLibraryEntry(
        id: UUID(),
        displayName: "Still Prepare",
        musicXMLFileName: "still-prepare.musicxml",
        importedAt: .now,
        audioFileName: nil,
        isBundled: true
    )
    let service = DelayedPreparationService(delays: [:])
    let viewModel = makeSelectionViewModel(
        entries: [entry],
        scoreURL: url,
        service: service,
        indexStore: PreparationTestIndexStore(failSaves: true),
        settleDelay: .zero
    )

    viewModel.selectEntryForPractice(entry.id)
    try await waitForPreparation(viewModel, entryID: entry.id)

    let preparedEntryIDs = await service.requests()
    #expect(preparedEntryIDs == [entry.id])
    #expect(viewModel.errorMessage?.contains("保存曲库选择失败") == true)
}

@Test
@MainActor
func cancellingSelectionDuringSettleLeavesNoSideEffects() async throws {
    let url = FileManager.default.temporaryDirectory.appending(
        path: "cancelled-selection-\(UUID().uuidString).musicxml"
    )
    try Data("<score-partwise/>".utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let entry = SongLibraryEntry(
        id: UUID(),
        displayName: "Cancelled",
        musicXMLFileName: "cancelled.musicxml",
        importedAt: .now,
        audioFileName: nil,
        isBundled: true
    )
    let service = DelayedPreparationService(delays: [:])
    let indexStore = PreparationTestIndexStore()
    let viewModel = makeSelectionViewModel(
        entries: [entry],
        scoreURL: url,
        service: service,
        indexStore: indexStore,
        settleDelay: .milliseconds(40)
    )

    viewModel.selectEntryForPractice(entry.id)
    await Task.yield()
    viewModel.cancelPracticePreparation()
    try await Task.sleep(for: .milliseconds(60))

    let savedEntryIDs = await indexStore.savedEntryIDs
    let preparedEntryIDs = await service.requests()
    #expect(savedEntryIDs.isEmpty)
    #expect(preparedEntryIDs.isEmpty)
    #expect(viewModel.practicePreparationState == .idle)
}


@Test
@MainActor
func preparationWithoutMeasureSpansIsRejectedAtTheLibraryBoundary() async throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "missing-measures-\(UUID().uuidString).musicxml")
    try Data("<score-partwise/>".utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let entryID = UUID()
    let entry = SongLibraryEntry(
        id: entryID,
        displayName: "Missing Measures",
        musicXMLFileName: "missing.musicxml",
        importedAt: .now,
        audioFileName: nil,
        isBundled: true
    )
    let appState = AppState()
    let guide = ARGuideViewModel(
        appState: appState,
        practiceSetupState: appState.practiceSetupState
    )
    let viewModel = SongLibraryViewModel(
        arGuideViewModel: guide,
        practicePreparationService: DelayedPreparationService(delays: [:], includesMeasureSpans: false),
        indexStore: PreparationTestIndexStore(),
        fileStore: PreparationTestFileStore(),
        audioImportService: PreparationTestAudioImporter(),
        bundledProvider: PreparationTestBundledProvider(entries: [entry], scoreURL: url),
        audioPlayer: PreparationTestAudioPlayer(),
        practiceProgressRepository: PreparationTestProgressRepository(),
        diagnosticsReporter: InMemoryDiagnosticsReporter(),
        initialSnapshot: .loaded(index: .empty, bundledEntries: [entry]),
        selectionSettleDelay: .zero
    )

    viewModel.selectEntryForPractice(entryID)
    try await waitForPreparationFailure(viewModel, entryID: entryID)

    guard case let .failure(failure) = viewModel.practicePreparationState else {
        Issue.record("Expected preparation failure")
        return
    }
    #expect(failure.code == .practiceMissingMeasureStructure)
    #expect(appState.practiceSetupState.preparedPracticeIdentity == nil)
}

@MainActor
private func waitForPreparation(
    _ viewModel: SongLibraryViewModel,
    entryID: UUID
) async throws {
    for _ in 0..<100 {
        if case let .ready(readyEntryID, _) = viewModel.practicePreparationState,
           readyEntryID == entryID {
            return
        }
        try await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("Timed out waiting for ready preparation")
}

@MainActor
private func waitForPreparationFailure(
    _ viewModel: SongLibraryViewModel,
    entryID: UUID
) async throws {
    for _ in 0..<100 {
        if case let .failure(failure) = viewModel.practicePreparationState,
           failure.entryID == entryID {
            return
        }
        try await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("Timed out waiting for preparation failure")
}

private actor PreparationTestIndexStore: SongLibraryIndexStoreProtocol {
    var value = SongLibraryIndex.empty
    private(set) var savedEntryIDs: [UUID] = []
    private let failSaves: Bool

    init(failSaves: Bool = false) {
        self.failSaves = failSaves
    }

    func load() throws -> SongLibraryIndex { value }
    func save(_ index: SongLibraryIndex) throws {
        guard failSaves == false else { throw CocoaError(.fileWriteUnknown) }
        value = index
        if let selectedEntryID = index.lastSelectedEntryID {
            savedEntryIDs.append(selectedEntryID)
        }
    }
}

@MainActor
private func makeSelectionViewModel(
    entries: [SongLibraryEntry],
    scoreURL: URL,
    service: DelayedPreparationService,
    indexStore: PreparationTestIndexStore,
    settleDelay: Duration
) -> SongLibraryViewModel {
    let appState = AppState()
    return SongLibraryViewModel(
        arGuideViewModel: ARGuideViewModel(
            appState: appState,
            practiceSetupState: appState.practiceSetupState
        ),
        practicePreparationService: service,
        indexStore: indexStore,
        fileStore: PreparationTestFileStore(),
        audioImportService: PreparationTestAudioImporter(),
        bundledProvider: PreparationTestBundledProvider(entries: entries, scoreURL: scoreURL),
        audioPlayer: PreparationTestAudioPlayer(),
        practiceProgressRepository: PreparationTestProgressRepository(),
        diagnosticsReporter: InMemoryDiagnosticsReporter(),
        initialSnapshot: .loaded(index: .empty, bundledEntries: entries),
        selectionSettleDelay: settleDelay
    )
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
    var currentTime: TimeInterval { 0 }
    var duration: TimeInterval { 0 }
    func play(entryID _: UUID, url _: URL) throws {}
    func pause() {}
    func stop() {}
    func seek(to _: TimeInterval) {}
    func isPlaying(entryID _: UUID) -> Bool { false }
}


private actor PreparationTestProgressRepository: PracticeProgressRepositoryProtocol {
    private var document: PracticeProgressDocument

    init(progress: SongPracticeProgress? = nil) {
        document = PracticeProgressDocument(songs: progress.map { [$0] } ?? [])
    }

    func load() -> PracticeProgressLoadResult { .loaded(document) }

    func progress(for identity: PracticeSongIdentity) -> SongPracticeProgress? {
        document.songs.first { $0.identity == identity }
    }

    func upsert(_ progress: SongPracticeProgress) {
        document.songs.removeAll { $0.identity == progress.identity }
        document.songs.append(progress)
    }

    func remove(songID: UUID) {
        document.songs.removeAll { $0.identity.songID == songID }
    }
}

@Test
@MainActor
func stalePreparedPracticeApplicationCannotOverwriteNewerSelection() async throws {
    let firstID = UUID()
    let secondID = UUID()
    let repository = DelayedIdentityProgressRepository(
        delays: [firstID: .milliseconds(80), secondID: .milliseconds(5)]
    )
    let session = PracticeSessionViewModel(
        pressDetectionService: PreparationRacePressDetectionService(),
        chordAttemptAccumulator: PreparationRaceChordAccumulator(),
        sleeper: TaskSleeper(),
        progressCoordinator: PracticeProgressCoordinator(repository: repository)
    )
    let appState = AppState()
    let guide = ARGuideViewModel(
        appState: appState,
        practiceSetupState: appState.practiceSetupState,
        pianoModeRegistry: PianoModeRegistryService(modes: []),
        makePracticeSessionViewModel: SinglePreparationRaceSessionProvider(session: session).callAsFunction
    )
    var selectedID = firstID
    let first = makeRacePreparedPractice(songID: firstID)
    let second = makeRacePreparedPractice(songID: secondID)

    let firstTask = Task { @MainActor in
        await guide.applyPreparedPractice(first, isCurrent: { selectedID == firstID })
    }
    try await Task.sleep(for: .milliseconds(10))
    selectedID = secondID
    let secondTask = Task { @MainActor in
        await guide.applyPreparedPractice(second, isCurrent: { selectedID == secondID })
    }

    let firstApplied = await firstTask.value
    let secondApplied = await secondTask.value

    #expect(firstApplied == false)
    #expect(secondApplied)
    #expect(session.songIdentity == second.identity)
    #expect(guide.latestPreparedPractice?.identity == second.identity)
}

private func makeRacePreparedPractice(songID: UUID) -> PreparedPractice {
    PreparedPractice(
        identity: PracticeSongIdentity(songID: songID, scoreRevision: songID.uuidString),
        steps: [PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1)])],
        file: ImportedMusicXMLFile(
            fileName: songID.uuidString,
            storedURL: URL(fileURLWithPath: "/dev/null"),
            importedAt: .now
        ),
        tempoMap: MusicXMLTempoMap(tempoEvents: []),
        pedalTimeline: nil,
        fermataTimeline: nil,
        attributeTimeline: nil,
        highlightGuides: [],
        measureSpans: [
            MusicXMLMeasureSpan(
                partID: "P1",
                measureNumber: 1,
                sourceMeasureIndex: 0,
                sourceMeasureNumberToken: "1",
                occurrenceIndex: 0,
                startTick: 0,
                endTick: 1
            )
        ],
        unsupportedNoteCount: 0
    )
}

private actor DelayedIdentityProgressRepository: PracticeProgressRepositoryProtocol {
    let delays: [UUID: Duration]

    init(delays: [UUID: Duration]) {
        self.delays = delays
    }

    func load() -> PracticeProgressLoadResult {
        .loaded(PracticeProgressDocument())
    }

    func progress(for identity: PracticeSongIdentity) async -> SongPracticeProgress? {
        if let delay = delays[identity.songID] {
            try? await Task.sleep(for: delay)
        }
        return nil
    }

    func upsert(_: SongPracticeProgress) {}
    func remove(songID _: UUID) {}
}

@MainActor
private final class SinglePreparationRaceSessionProvider: @unchecked Sendable {
    private let session: PracticeSessionViewModel

    init(session: PracticeSessionViewModel) {
        self.session = session
    }

    func callAsFunction(_: String?) -> PracticeSessionViewModel {
        session
    }
}

private struct PreparationRacePressDetectionService: PressDetectionServiceProtocol {
    func detectPressedNotes(
        fingerTips _: FingerTipsSnapshot,
        keyboardGeometry _: PianoKeyboardGeometry?,
        at _: Date
    ) -> Set<Int> {
        []
    }
}

private final class PreparationRaceChordAccumulator: ChordAttemptAccumulatorProtocol {
    func register(
        pressedNotes _: Set<Int>,
        expectedNotes _: [Int],
        tolerance _: Int,
        at _: Date
    ) -> StepAttemptMatchResult {
        .insufficientEvidence
    }

    func reset() {}
}

private actor FailingLibraryPreparationService: PracticePreparationServiceProtocol {
    func prepare(songID _: UUID, from _: URL, file _: ImportedMusicXMLFile) async throws -> PreparedPractice {
        throw PracticePreparationError.xmlParseFailed(
            line: 12,
            column: 4,
            reason: "Mismatched closing tag"
        )
    }
}

@Test
@MainActor
func preparationFailureUsesOneTypedEventAndReportsExportAcceptance() async throws {
    let fixture = makeFailurePreparationFixture(persistResult: true)

    fixture.viewModel.selectEntryForPractice(fixture.entryID)
    let firstFailure = try await waitForLoggedPreparationFailure(fixture.viewModel)
    let firstEvents = await fixture.reporter.events

    #expect(fixture.viewModel.wasSelectedPreparationFailureRecorded)
    #expect(firstEvents == [firstFailure.diagnosticEvent])

    fixture.viewModel.retrySelectedPracticePreparation()
    let secondFailure = try await waitForLoggedPreparationFailure(
        fixture.viewModel,
        excluding: firstFailure.id
    )
    let secondEvents = await fixture.reporter.events

    #expect(secondFailure.id != firstFailure.id)
    #expect(secondEvents.count == 2)
    #expect(secondEvents.last == secondFailure.diagnosticEvent)
}

@Test
@MainActor
func preparationFailureDoesNotClaimExportWhenStoreRejectsEvent() async throws {
    let fixture = makeFailurePreparationFixture(persistResult: false)

    fixture.viewModel.selectEntryForPractice(fixture.entryID)
    _ = try await waitForPreparationFailure(fixture.viewModel, entryID: fixture.entryID)
    try await waitForDiagnosticEventCount(fixture.reporter, count: 1)

    #expect(fixture.viewModel.wasSelectedPreparationFailureRecorded == false)
    #expect(await fixture.reporter.events.count == 1)
}


private func waitForDiagnosticEventCount(
    _ reporter: InMemoryDiagnosticsReporter,
    count: Int
) async throws {
    for _ in 0..<100 {
        if await reporter.events.count >= count {
            return
        }
        try await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("Timed out waiting for diagnostic events")
}

@MainActor
private func makeFailurePreparationFixture(
    persistResult: Bool
) -> (
    viewModel: SongLibraryViewModel,
    reporter: InMemoryDiagnosticsReporter,
    entryID: UUID
) {
    let scoreURL = FileManager.default.temporaryDirectory.appending(
        path: "failure-\(UUID().uuidString).musicxml"
    )
    let entryID = UUID()
    let entry = SongLibraryEntry(
        id: entryID,
        displayName: "Broken Score",
        musicXMLFileName: scoreURL.lastPathComponent,
        importedAt: .now,
        audioFileName: nil,
        isBundled: true
    )
    let reporter = InMemoryDiagnosticsReporter(persistResult: persistResult)
    let appState = AppState()
    let guide = ARGuideViewModel(
        appState: appState,
        practiceSetupState: appState.practiceSetupState
    )
    let viewModel = SongLibraryViewModel(
        arGuideViewModel: guide,
        practicePreparationService: FailingLibraryPreparationService(),
        indexStore: PreparationTestIndexStore(),
        fileStore: PreparationTestFileStore(),
        audioImportService: PreparationTestAudioImporter(),
        bundledProvider: PreparationTestBundledProvider(entries: [entry], scoreURL: scoreURL),
        audioPlayer: PreparationTestAudioPlayer(),
        practiceProgressRepository: PreparationTestProgressRepository(),
        diagnosticsReporter: reporter,
        initialSnapshot: .loaded(index: .empty, bundledEntries: [entry]),
        selectionSettleDelay: .zero
    )
    return (viewModel, reporter, entryID)
}

@MainActor
private func waitForLoggedPreparationFailure(
    _ viewModel: SongLibraryViewModel,
    excluding previousID: UUID? = nil
) async throws -> LibraryPracticePreparationFailure {
    for _ in 0..<100 {
        if case let .failure(failure) = viewModel.practicePreparationState,
           failure.id != previousID,
           viewModel.wasSelectedPreparationFailureRecorded
        {
            return failure
        }
        try await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("Timed out waiting for logged preparation failure")
    throw CancellationError()
}

@Test
@MainActor
func directPracticeLaunchPreservesSavedResumeWhenSettingsAreUnchanged() async throws {
    let songID = UUID()
    let identity = PracticeSongIdentity(songID: songID, scoreRevision: songID.uuidString)
    let secondSource = PracticeSourceMeasureID(
        partID: "P1",
        sourceMeasureIndex: 1,
        sourceNumberToken: "2"
    )
    let secondOccurrence = PracticeMeasureOccurrenceID(
        sourceMeasureID: secondSource,
        occurrenceIndex: 1
    )
    let passage = try #require(PracticePassage(start: secondOccurrence, end: secondOccurrence))
    let configuration = PracticeRoundConfiguration(
        passage: passage,
        handMode: .right,
        tempoScale: 0.75,
        loopEnabled: true,
        requiredSuccesses: 3
    )
    let progress = SongPracticeProgress(
        identity: identity,
        activeConfiguration: configuration,
        resumePoint: PracticeResumePoint(
            occurrenceID: secondOccurrence,
            stepIndex: 1,
            updatedAt: .now
        ),
        updatedAt: .now
    )
    let fixture = makeDirectLaunchFixture(songID: songID, progress: progress)

    fixture.viewModel.selectEntryForPractice(songID)
    try await waitForPreparation(fixture.viewModel, entryID: songID)

    #expect(fixture.session.currentStepIndex == 1)
    #expect(fixture.session.isRestoredSessionPaused)
    #expect(fixture.viewModel.startSelectedPractice())
    #expect(fixture.session.currentStepIndex == 1)
    #expect(fixture.session.isRestoredSessionPaused)
}

@Test
@MainActor
func directPracticeLaunchAppliesEditedPendingConfiguration() async throws {
    let songID = UUID()
    let fixture = makeDirectLaunchFixture(songID: songID, progress: nil)

    fixture.viewModel.selectEntryForPractice(songID)
    try await waitForPreparation(fixture.viewModel, entryID: songID)
    let secondSpan = try #require(fixture.session.measureSpans.last)
    let passage = try #require(
        PracticePassage(start: secondSpan.occurrenceID, end: secondSpan.occurrenceID)
    )
    fixture.session.roundConfigurationController.pendingPassage = passage
    fixture.session.roundConfigurationController.pendingTempoScale = 0.5

    #expect(fixture.viewModel.startSelectedPractice())
    #expect(fixture.session.activeRoundConfiguration?.passage == passage)
    #expect(fixture.session.activeRoundConfiguration?.tempoScale == 0.5)
    #expect(fixture.session.currentStepIndex == 1)
}

@MainActor
private func makeDirectLaunchFixture(
    songID: UUID,
    progress: SongPracticeProgress?
) -> (
    viewModel: SongLibraryViewModel,
    session: PracticeSessionViewModel
) {
    let repository = PreparationTestProgressRepository(progress: progress)
    let session = PracticeSessionViewModel(
        pressDetectionService: PreparationRacePressDetectionService(),
        chordAttemptAccumulator: PreparationRaceChordAccumulator(),
        sleeper: TaskSleeper(),
        progressCoordinator: PracticeProgressCoordinator(
            repository: repository,
            checkpointDelay: .seconds(60)
        )
    )
    let appState = AppState()
    let guide = ARGuideViewModel(
        appState: appState,
        practiceSetupState: appState.practiceSetupState,
        pianoModeRegistry: PianoModeRegistryService(modes: []),
        makePracticeSessionViewModel: SinglePreparationRaceSessionProvider(
            session: session
        ).callAsFunction
    )
    let scoreURL = FileManager.default.temporaryDirectory.appending(
        path: "direct-launch-\(songID.uuidString).musicxml"
    )
    let entry = SongLibraryEntry(
        id: songID,
        displayName: "Direct Launch",
        musicXMLFileName: scoreURL.lastPathComponent,
        importedAt: .now,
        audioFileName: nil,
        isBundled: true
    )
    let viewModel = SongLibraryViewModel(
        arGuideViewModel: guide,
        practicePreparationService: DelayedPreparationService(delays: [:]),
        indexStore: PreparationTestIndexStore(),
        fileStore: PreparationTestFileStore(),
        audioImportService: PreparationTestAudioImporter(),
        bundledProvider: PreparationTestBundledProvider(entries: [entry], scoreURL: scoreURL),
        audioPlayer: PreparationTestAudioPlayer(),
        practiceProgressRepository: repository,
        diagnosticsReporter: InMemoryDiagnosticsReporter(),
        initialSnapshot: .loaded(index: .empty, bundledEntries: [entry]),
        selectionSettleDelay: .zero
    )
    return (viewModel, session)
}
