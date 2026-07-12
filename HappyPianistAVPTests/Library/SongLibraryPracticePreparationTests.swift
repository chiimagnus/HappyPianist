import Foundation
@testable import HappyPianistAVP
import Testing

private actor DelayedPreparationService: PracticePreparationServiceProtocol {
    let delays: [UUID: Duration]
    let includesMeasureSpans: Bool

    init(delays: [UUID: Duration], includesMeasureSpans: Bool = true) {
        self.delays = delays
        self.includesMeasureSpans = includesMeasureSpans
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
            measureSpans: includesMeasureSpans ? [MusicXMLMeasureSpan(
                partID: "P1",
                measureNumber: 1,
                sourceMeasureIndex: 0,
                sourceMeasureNumberToken: "1",
                occurrenceIndex: 0,
                startTick: 0,
                endTick: 1
            )] : [],
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
        bundledProvider: PreparationTestBundledProvider(entries: entries, scoreURL: url),
        audioPlayer: PreparationTestAudioPlayer(),
        practiceProgressRepository: PreparationTestProgressRepository(),
        diagnosticsReporter: InMemoryDiagnosticsReporter()
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
    let viewModel = SongLibraryViewModel(
        appState: appState,
        practicePreparationService: DelayedPreparationService(delays: [:], includesMeasureSpans: false),
        indexStore: PreparationTestIndexStore(),
        fileStore: PreparationTestFileStore(),
        audioImportService: PreparationTestAudioImporter(),
        bundledProvider: PreparationTestBundledProvider(entries: [entry], scoreURL: url),
        audioPlayer: PreparationTestAudioPlayer(),
        practiceProgressRepository: PreparationTestProgressRepository(),
        diagnosticsReporter: InMemoryDiagnosticsReporter()
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
        slurTimeline: nil,
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
        fingerTips _: [String: SIMD3<Float>],
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
    try await Task.sleep(for: .milliseconds(20))

    #expect(fixture.viewModel.wasSelectedPreparationFailureRecorded == false)
    #expect(await fixture.reporter.events.count == 1)
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
    let viewModel = SongLibraryViewModel(
        appState: AppState(),
        practicePreparationService: FailingLibraryPreparationService(),
        indexStore: PreparationTestIndexStore(),
        fileStore: PreparationTestFileStore(),
        audioImportService: PreparationTestAudioImporter(),
        bundledProvider: PreparationTestBundledProvider(entries: [entry], scoreURL: scoreURL),
        audioPlayer: PreparationTestAudioPlayer(),
        practiceProgressRepository: PreparationTestProgressRepository(),
        diagnosticsReporter: reporter
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
