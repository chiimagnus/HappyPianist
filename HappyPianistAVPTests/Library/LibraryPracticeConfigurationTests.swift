import Foundation
@testable import HappyPianistAVP
import Testing

@MainActor
@Test
func freshLibraryScoreUsesFullScoreDefaults() async throws {
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "r1")
    let spans = makeLibraryConfigurationSpans()
    let session = makeLibraryConfigurationSession(repository: LibraryConfigurationRepository(progresses: []))

    session.installPreparedSteps(
        makeLibraryConfigurationSteps(),
        identity: identity,
        tempoMap: MusicXMLTempoMap(tempoEvents: []),
        measureSpans: spans
    )
    await session.restoreProgressIfAvailable()

    let configuration = try #require(session.activeRoundConfiguration)
    #expect(configuration.passage.start == spans.first?.occurrenceID)
    #expect(configuration.passage.end == spans.last?.occurrenceID)
    #expect(configuration.handMode == .both)
    #expect(configuration.tempoScale == 1)
    #expect(configuration.loopEnabled == false)
    #expect(configuration.requiredSuccesses == 3)
    #expect(session.currentStepIndex == session.activeRange?.firstStepIndex)
}

@MainActor
@Test
func savedLibraryConfigurationAndResumePointAreRestored() async throws {
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "r1")
    let spans = makeLibraryConfigurationSpans()
    let passage = try #require(PracticePassage(start: spans[1].occurrenceID, end: spans[2].occurrenceID))
    let savedConfiguration = PracticeRoundConfiguration(
        passage: passage,
        handMode: .left,
        tempoScale: 0.75,
        loopEnabled: true,
        requiredSuccesses: 4
    )
    let progress = SongPracticeProgress(
        identity: identity,
        activeConfiguration: savedConfiguration,
        resumePoint: PracticeResumePoint(
            occurrenceID: spans[2].occurrenceID,
            stepIndex: 2,
            updatedAt: .now
        ),
        updatedAt: .now
    )
    let session = makeLibraryConfigurationSession(
        repository: LibraryConfigurationRepository(progresses: [progress])
    )

    session.installPreparedSteps(
        makeLibraryConfigurationSteps(),
        identity: identity,
        tempoMap: MusicXMLTempoMap(tempoEvents: []),
        measureSpans: spans
    )
    await session.restoreProgressIfAvailable()

    #expect(session.activeRoundConfiguration == savedConfiguration)
    #expect(session.roundConfigurationController.pendingConfiguration == savedConfiguration)
    #expect(session.currentStepIndex == 2)
    #expect(session.isRestoredSessionPaused)
}

@MainActor
@Test
func scoreRevisionMismatchUsesFreshDefaultsInsteadOfOldProgress() async throws {
    let songID = UUID()
    let storedIdentity = PracticeSongIdentity(songID: songID, scoreRevision: "r1")
    let currentIdentity = PracticeSongIdentity(songID: songID, scoreRevision: "r2")
    let spans = makeLibraryConfigurationSpans()
    let savedPassage = try #require(PracticePassage(start: spans[1].occurrenceID, end: spans[1].occurrenceID))
    let progress = SongPracticeProgress(
        identity: storedIdentity,
        activeConfiguration: PracticeRoundConfiguration(
            passage: savedPassage,
            handMode: .right,
            tempoScale: 0.6,
            loopEnabled: true,
            requiredSuccesses: 5
        ),
        updatedAt: .now
    )
    let session = makeLibraryConfigurationSession(
        repository: LibraryConfigurationRepository(progresses: [progress])
    )

    session.installPreparedSteps(
        makeLibraryConfigurationSteps(),
        identity: currentIdentity,
        tempoMap: MusicXMLTempoMap(tempoEvents: []),
        measureSpans: spans
    )
    await session.restoreProgressIfAvailable()

    let configuration = try #require(session.activeRoundConfiguration)
    #expect(configuration.passage.start == spans.first?.occurrenceID)
    #expect(configuration.passage.end == spans.last?.occurrenceID)
    #expect(configuration.handMode == .both)
    #expect(configuration.tempoScale == 1)
    #expect(configuration.loopEnabled == false)
    #expect(session.sessionProgress == nil)
    #expect(session.currentStepIndex == 0)
}

@MainActor
@Test
func selectingAThenBThenARestoresPersistedStateAndDiscardsDrafts() async throws {
    let identityA = PracticeSongIdentity(songID: UUID(), scoreRevision: "a1")
    let identityB = PracticeSongIdentity(songID: UUID(), scoreRevision: "b1")
    let spans = makeLibraryConfigurationSpans()
    let savedPassageA = try #require(PracticePassage(start: spans[1].occurrenceID, end: spans[2].occurrenceID))
    let savedConfigurationA = PracticeRoundConfiguration(
        passage: savedPassageA,
        handMode: .left,
        tempoScale: 0.8,
        loopEnabled: true,
        requiredSuccesses: 4
    )
    let progressA = SongPracticeProgress(
        identity: identityA,
        activeConfiguration: savedConfigurationA,
        resumePoint: PracticeResumePoint(
            occurrenceID: spans[1].occurrenceID,
            stepIndex: 1,
            updatedAt: .now
        ),
        updatedAt: .now
    )
    let session = makeLibraryConfigurationSession(
        repository: LibraryConfigurationRepository(progresses: [progressA])
    )

    session.installPreparedSteps(
        makeLibraryConfigurationSteps(),
        identity: identityA,
        tempoMap: MusicXMLTempoMap(tempoEvents: []),
        measureSpans: spans
    )
    await session.restoreProgressIfAvailable()
    session.roundConfigurationController.pendingHandMode = .right
    session.roundConfigurationController.pendingTempoScale = 0.5

    session.installPreparedSteps(
        makeLibraryConfigurationSteps(),
        identity: identityB,
        tempoMap: MusicXMLTempoMap(tempoEvents: []),
        measureSpans: spans
    )
    await session.restoreProgressIfAvailable()

    #expect(session.roundConfigurationController.pendingHandMode == .both)
    #expect(session.roundConfigurationController.pendingTempoScale == 1)
    #expect(session.roundConfigurationController.pendingLoopEnabled == false)
    session.roundConfigurationController.pendingTempoScale = 0.65

    session.installPreparedSteps(
        makeLibraryConfigurationSteps(),
        identity: identityA,
        tempoMap: MusicXMLTempoMap(tempoEvents: []),
        measureSpans: spans
    )
    await session.restoreProgressIfAvailable()

    #expect(session.activeRoundConfiguration == savedConfigurationA)
    #expect(session.roundConfigurationController.pendingConfiguration == savedConfigurationA)
    #expect(session.currentStepIndex == 1)
}

@MainActor
private func makeLibraryConfigurationSession(
    repository: LibraryConfigurationRepository
) -> PracticeSessionViewModel {
    PracticeSessionViewModel(
        pressDetectionService: LibraryConfigurationPressDetectionService(),
        chordAttemptAccumulator: LibraryConfigurationChordAccumulator(),
        sleeper: TaskSleeper(),
        progressCoordinator: PracticeProgressCoordinator(
            repository: repository,
            checkpointDelay: .seconds(60)
        )
    )
}

private func makeLibraryConfigurationSteps() -> [PracticeStep] {
    [
        PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1)]),
        PracticeStep(tick: 480, notes: [PracticeStepNote(midiNote: 62, staff: 1)]),
        PracticeStep(tick: 960, notes: [PracticeStepNote(midiNote: 64, staff: 1)]),
    ]
}

private func makeLibraryConfigurationSpans() -> [MusicXMLMeasureSpan] {
    [
        MusicXMLMeasureSpan(partID: "P1", measureNumber: 1, sourceMeasureIndex: 0, sourceMeasureNumberToken: "1", occurrenceIndex: 0, startTick: 0, endTick: 480),
        MusicXMLMeasureSpan(partID: "P1", measureNumber: 2, sourceMeasureIndex: 1, sourceMeasureNumberToken: "2", occurrenceIndex: 1, startTick: 480, endTick: 960),
        MusicXMLMeasureSpan(partID: "P1", measureNumber: 3, sourceMeasureIndex: 2, sourceMeasureNumberToken: "3", occurrenceIndex: 2, startTick: 960, endTick: 1_440),
    ]
}

private actor LibraryConfigurationRepository: PracticeProgressRepositoryProtocol {
    private var progresses: [PracticeSongIdentity: SongPracticeProgress]

    init(progresses: [SongPracticeProgress]) {
        self.progresses = Dictionary(uniqueKeysWithValues: progresses.map { ($0.identity, $0) })
    }

    func load() -> PracticeProgressLoadResult {
        .loaded(PracticeProgressDocument(songs: Array(progresses.values)))
    }

    func progress(for identity: PracticeSongIdentity) -> SongPracticeProgress? {
        progresses[identity]
    }

    func upsert(_ progress: SongPracticeProgress) {
        progresses[progress.identity] = progress
    }

    func remove(songID: UUID) {
        progresses = progresses.filter { $0.key.songID != songID }
    }
}

private struct LibraryConfigurationPressDetectionService: PressDetectionServiceProtocol {
    func detectPressedNotes(
        fingerTips _: [String: SIMD3<Float>],
        keyboardGeometry _: PianoKeyboardGeometry?,
        at _: Date
    ) -> Set<Int> {
        []
    }
}

private final class LibraryConfigurationChordAccumulator: ChordAttemptAccumulatorProtocol {
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
