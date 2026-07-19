import Foundation
@testable import HappyPianistAVP
import Testing

@MainActor
@Test
func historicalPreferencesApplyToCurrentFullPassageWithoutPersistingDefaultsOrOldFacts() async throws {
    let songID = UUID()
    let oldIdentity = PracticeSongIdentity(songID: songID, scoreRevision: "old")
    let currentIdentity = PracticeSongIdentity(songID: songID, scoreRevision: "current")
    let spans = historicalApplicationSpans()
    let oldSource = PracticeSourceMeasureID(partID: "old-part", sourceMeasureIndex: 99)
    let oldOccurrence = PracticeMeasureOccurrenceID(sourceMeasureID: oldSource, occurrenceIndex: 99)
    let oldProgress = try SongPracticeProgress(
        identity: oldIdentity,
        activeConfiguration: PracticeRoundConfiguration(
            passage: #require(PracticePassage(start: oldOccurrence, end: oldOccurrence)),
            handMode: .left,
            tempoScale: 0.65,
            loopEnabled: true,
            requiredSuccesses: 4
        ),
        resumePoint: PracticeResumePoint(
            occurrenceID: oldOccurrence,
            stepIndex: 99,
            updatedAt: .now
        ),
        measureFacts: [MeasurePracticeFacts(
            sourceMeasureID: oldSource,
            handMode: .left,
            state: .stable,
            successfulAttempts: 9
        )],
        updatedAt: .now
    )
    let defaults = HistoricalApplicationDefaultsStore()
    let session = historicalApplicationSession(
        defaults: defaults,
        repository: HistoricalApplicationRepository(progress: oldProgress)
    )
    installHistoricalApplicationScore(session, identity: currentIdentity, spans: spans)

    await session.applyLaunchRestorePolicy(.historicalPreferences(
        PracticeHistoricalPreferences(
            handMode: .left,
            tempoScale: 0.65,
            loopEnabled: true,
            requiredSuccesses: 4
        )
    ))

    let active = try #require(session.activeRoundConfiguration)
    #expect(active.passage.start == spans.first?.occurrenceID)
    #expect(active.passage.end == spans.last?.occurrenceID)
    #expect(active.handMode == .left)
    #expect(active.tempoScale == 0.65)
    #expect(active.loopEnabled)
    #expect(active.requiredSuccesses == 4)
    #expect(session.roundConfigurationController.pendingConfiguration == active)
    #expect(session.currentStepIndex == session.activeRange?.firstStepIndex)
    #expect(session.sessionProgress == nil)
    #expect(session.isRestoredSessionPaused == false)
    #expect(defaults.saveCount == 0)
    #expect(defaults.tempoScale == 0.55)
    #expect(defaults.loopEnabled)
    #expect(defaults.requiredSuccesses == 2)
}

@MainActor
private func historicalApplicationSession(
    defaults: HistoricalApplicationDefaultsStore,
    repository: HistoricalApplicationRepository?
) -> PracticeSessionViewModel {
    PracticeSessionViewModel(
        chordAttemptAccumulator: HistoricalApplicationChordAccumulator(),
        sleeper: TaskSleeper(),
        sequencerPlaybackService: HistoricalApplicationPlaybackService(),
        audioStepAttemptAccumulator: AudioStepAttemptAccumulator(),
        handPianoActivityGate: HandPianoActivityGate(),
        settingsProvider: HistoricalApplicationSettingsProvider(),
        roundDefaultsStore: defaults,
        progressCoordinator: repository.map {
            PracticeProgressCoordinator(repository: $0, checkpointDelay: .seconds(60))
        }
    )
}

@MainActor
private func installHistoricalApplicationScore(
    _ session: PracticeSessionViewModel,
    identity: PracticeSongIdentity,
    spans: [MusicXMLMeasureSpan]
) {
    let notes = historicalApplicationPerformanceNotes()
    let plan = makeTestScorePerformancePlan(identity: identity, notes: notes)
    session.installPreparedSteps(
        PracticeStepBuilder().buildSteps(from: plan).steps,
        identity: identity,
        performancePlan: plan,
        notationProjection: ScoreNotationProjection(
            plan: plan,
            sourceScore: makeTestMusicXMLScore(notes: notes)
        ),
        measureSpans: spans
    )
}

private func historicalApplicationPerformanceNotes() -> [TestScorePerformanceNote] {
    [
        TestScorePerformanceNote(midiNote: 60, onTick: 0),
        TestScorePerformanceNote(midiNote: 62, onTick: 480, staff: 2),
    ]
}

private func historicalApplicationSpans() -> [MusicXMLMeasureSpan] {
    [
        MusicXMLMeasureSpan(partID: "P1", measureNumber: 1, sourceMeasureIndex: 0, sourceMeasureNumberToken: "1", occurrenceIndex: 0, startTick: 0, endTick: 480),
        MusicXMLMeasureSpan(partID: "P1", measureNumber: 2, sourceMeasureIndex: 1, sourceMeasureNumberToken: "2", occurrenceIndex: 1, startTick: 480, endTick: 960),
    ]
}

private final class HistoricalApplicationDefaultsStore: PracticeRoundDefaultsStoreProtocol {
    var tempoScale = 0.55
    var loopEnabled = true
    var requiredSuccesses = 2
    private(set) var saveCount = 0

    func save(
        handMode _: PracticeHandMode,
        manualAdvanceMode _: ManualAdvanceMode,
        soundRoutingSettings _: PracticeSoundRoutingSettings,
        tempoScale _: Double,
        loopEnabled _: Bool,
        requiredSuccesses _: Int
    ) {
        saveCount += 1
    }
}

private struct HistoricalApplicationSettingsProvider: PracticeSessionSettingsProviderProtocol {
    let manualAdvanceMode: ManualAdvanceMode = .step
    let practiceHandMode: PracticeHandMode = .right
    let soundRoutingSettings = PracticeSoundRoutingSettings(
        outputRoute: .localSampler,
        midiDestinationUniqueID: nil,
        sendLocalControlOff: false
    )
}

private actor HistoricalApplicationRepository: PracticeProgressRepositoryProtocol {
    private var progress: SongPracticeProgress?

    init(progress: SongPracticeProgress?) {
        self.progress = progress
    }

    func load() -> PracticeProgressLoadResult {
        .loaded(PracticeProgressDocument())
    }

    func progress(for identity: PracticeSongIdentity) -> SongPracticeProgress? {
        progress?.identity == identity ? progress : nil
    }

    func history(for songID: UUID) -> PracticeSongHistoryLoadResult {
        .loaded(PracticeSongHistory(
            songID: songID,
            progresses: progress.map { $0.identity.songID == songID ? [$0] : [] } ?? [],
            scoreMetadata: [],
            sessions: []
        ))
    }

    func upsert(_ progress: SongPracticeProgress) {
        self.progress = progress
    }

    func upsert(_: SongScorePracticeMetadata) {}
    func remove(songID: UUID) {
        if progress?.identity.songID == songID { progress = nil }
    }
}

private final class HistoricalApplicationChordAccumulator: ChordAttemptAccumulatorProtocol {
    func register(
        pressedNotes _: Set<Int>,
        expectedNotes _: [Int],
        at _: PerformanceMonotonicInstant
    ) -> StepAttemptMatchResult {
        .insufficientEvidence
    }

    func reset() {}
}

private final class HistoricalApplicationPlaybackService: PracticeSequencerPlaybackServiceProtocol {
    func warmUp() throws {}
    func stop(resetCommands _: [PerformanceTransportCommand]) {}
    func load(sequence _: PracticeSequencerSequence) throws {}
    func play(fromSeconds _: TimeInterval) throws {}
    func currentSeconds() -> TimeInterval {
        0
    }

    func playOneShot(commands _: [PracticePlaybackCommand], durationSeconds _: TimeInterval) throws {}
    func execute(commands _: [PracticePlaybackCommand]) throws {}
    func stopAllLiveNotes() {}
}
