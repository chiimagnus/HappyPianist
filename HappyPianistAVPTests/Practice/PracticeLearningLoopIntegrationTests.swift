import Foundation
@testable import HappyPianistAVP
import Testing

@MainActor
@Test
func configuredAttemptPersistsAndRebuildsAsPausedResume() async throws {
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "fixture-r1")
    let repository = LearningLoopRepository()
    let firstCoordinator = PracticeProgressCoordinator(repository: repository, checkpointDelay: .seconds(60))
    let firstPlayback = LearningLoopPlaybackService()
    let firstSession = makeLearningLoopSession(
        playback: firstPlayback,
        coordinator: firstCoordinator
    )
    let span = learningLoopSpan()
    firstSession.songIdentity = identity
    firstSession.installTestPerformanceNotes(
        [TestScorePerformanceNote(midiNote: 60, onTick: 0)],
        measureSpans: [span]
    )
    firstSession.roundConfigurationController.pendingRequiredSuccesses = 1
    _ = firstSession.applyPendingRoundConfiguration()
    await firstSession.applyLaunchRestorePolicy(.freshDefaults)
    firstSession.startGuidingIfReady()
    firstSession.recordAttemptOutcome(matchedLearningLoopOutcome())
    await firstSession.flushAndShutdown()

    let saved = try #require(await repository.progress(for: identity))
    #expect(saved.measureFacts.first?.state == .pitchStepStable)
    #expect(saved.resumePoint?.stepIndex == 0)

    let secondCoordinator = PracticeProgressCoordinator(repository: repository, checkpointDelay: .seconds(60))
    let secondPlayback = LearningLoopPlaybackService()
    let secondSession = makeLearningLoopSession(
        playback: secondPlayback,
        coordinator: secondCoordinator
    )
    secondSession.songIdentity = identity
    secondSession.installTestPerformanceNotes(
        [TestScorePerformanceNote(midiNote: 60, onTick: 0)],
        measureSpans: [span]
    )
    await secondSession.applyLaunchRestorePolicy(.exactAvailable)

    #expect(secondSession.state == .ready)
    #expect(secondSession.isRestoredSessionPaused)
    #expect(secondPlayback.oneShotCount == 0)
    #expect(secondPlayback.playCount == 0)
}

@Test
func revisionMismatchDoesNotRestoreOldScoreProgress() async {
    let songID = UUID()
    let oldIdentity = PracticeSongIdentity(songID: songID, scoreRevision: "old")
    let repository = LearningLoopRepository(
        initial: SongPracticeProgress(identity: oldIdentity, updatedAt: .now)
    )
    let coordinator = PracticeProgressCoordinator(repository: repository)

    let session = await coordinator.begin(
        identity: PracticeSongIdentity(songID: songID, scoreRevision: "new")
    )

    #expect(session.progress == nil)
}

@MainActor
@Test
func completedPassagePersistsAssessmentOnceAndFinishesAnalyzerRound() async throws {
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "assessment-r1")
    let progressRepository = LearningLoopRepository()
    let progressCoordinator = PracticeProgressCoordinator(
        repository: progressRepository,
        checkpointDelay: .seconds(60)
    )
    let sessionRepository = LearningLoopSessionRepository()
    let recorder = PracticeSessionRecorder(
        repository: sessionRepository,
        performanceAnalyzer: PracticePerformanceAnalyzer()
    )
    await recorder.beginVisit(id: UUID(), songID: identity.songID, sceneIsActive: true)
    await recorder.bindIdentity(identity)
    let session = makeLearningLoopSession(
        playback: LearningLoopPlaybackService(),
        coordinator: progressCoordinator,
        recorder: recorder
    )
    session.songIdentity = identity
    session.installTestPerformanceNotes(
        [TestScorePerformanceNote(midiNote: 60, onTick: 0, offTick: 480)],
        measureSpans: [learningLoopSpan()]
    )
    session.roundConfigurationController.pendingRequiredSuccesses = 1
    _ = session.applyPendingRoundConfiguration()
    await session.applyLaunchRestorePolicy(.freshDefaults)
    session.startGuidingIfReady()
    await session.waitForSessionRecorderEvents()

    let instant = PerformanceClock.live().now()
    await recorder.record(PerformanceObservation(
        source: .init(kind: .midi1, id: "midi:integration", generation: 1),
        timing: .init(
            host: instant,
            source: nil,
            correctedHost: instant,
            mapping: nil,
            provenance: .hostOnly
        ),
        event: .noteOn(note: 60, velocity: .init(midi1: 90))
    ))
    session.recordAttemptOutcome(matchedLearningLoopOutcome())
    session.advanceToNextStep()
    await session.waitForSessionRecorderEvents()

    let firstSummary = try #require(session.sessionProgress?.measureFacts.first?.performanceMaturity)
    #expect(firstSummary.metricSummaries.contains { $0.dimension == .exactPitch })
    #expect(try #require(await recorder.analysisSnapshot()).isRunning == false)

    session.recordPassageCompletion()
    await session.waitForSessionRecorderEvents()
    #expect(session.sessionProgress?.measureFacts.first?.performanceMaturity == firstSummary)

    #expect(await session.flushProgress() == .saved)
    let saved = try #require(await progressRepository.progress(for: identity))
    #expect(saved.measureFacts.first?.performanceMaturity == firstSummary)
}

@MainActor
private func makeLearningLoopSession(
    playback: LearningLoopPlaybackService,
    coordinator: PracticeProgressCoordinator,
    recorder: PracticeSessionRecorder? = nil
) -> PracticeSessionViewModel {
    PracticeSessionViewModel(
        chordAttemptAccumulator: LearningLoopChordAccumulator(),
        sleeper: TaskSleeper(),
        sequencerPlaybackService: playback,
        progressCoordinator: coordinator,
        sessionRecorder: recorder
    )
}

private actor LearningLoopSessionRepository: PracticeSessionRepositoryProtocol {
    func upsert(_: PracticeSessionRecord) {}
    func abandonLiveSession(id _: UUID) {}
}

private func learningLoopSpan() -> MusicXMLMeasureSpan {
    MusicXMLMeasureSpan(
        partID: "P1",
        measureNumber: 1,
        sourceMeasureIndex: 0,
        sourceMeasureNumberToken: "1",
        occurrenceIndex: 0,
        startTick: 0,
        endTick: 480
    )
}

private func matchedLearningLoopOutcome() -> StepAttemptMatchResult {
    .matched
}

private actor LearningLoopRepository: PracticeProgressRepositoryProtocol {
    private var stored: [PracticeSongIdentity: SongPracticeProgress]

    init(initial: SongPracticeProgress? = nil) {
        stored = initial.map { [$0.identity: $0] } ?? [:]
    }

    func load() -> PracticeProgressLoadResult {
        .loaded(PracticeProgressDocument(songs: Array(stored.values)))
    }

    func progress(for identity: PracticeSongIdentity) -> SongPracticeProgress? {
        stored[identity]
    }

    func history(for songID: UUID) -> PracticeSongHistoryLoadResult {
        .loaded(PracticeSongHistory(
            songID: songID,
            progresses: stored.values.filter { $0.identity.songID == songID },
            scoreMetadata: [],
            sessions: []
        ))
    }

    func upsert(_ progress: SongPracticeProgress) {
        stored[progress.identity] = progress
    }

    func upsert(_: SongScorePracticeMetadata) {}

    func remove(songID: UUID) {
        stored = stored.filter { $0.key.songID != songID }
    }
}

private final class LearningLoopPlaybackService: PracticeSequencerPlaybackServiceProtocol {
    private(set) var oneShotCount = 0
    private(set) var playCount = 0
    func warmUp() throws {}
    func stop(resetCommands _: [PerformanceTransportCommand]) {}
    func load(sequence _: PracticeSequencerSequence) throws {}
    func play(fromSeconds _: TimeInterval) throws {
        playCount += 1
    }

    func currentSeconds() -> TimeInterval {
        0
    }

    func playOneShot(commands _: [PracticePlaybackCommand], durationSeconds _: TimeInterval) throws {
        oneShotCount += 1
    }

    func execute(commands _: [PracticePlaybackCommand]) throws {}
    func stopAllLiveNotes() {}
}

private final class LearningLoopChordAccumulator: ChordAttemptAccumulatorProtocol {
    func register(
        pressedNotes _: Set<Int>,
        expectedNotes _: [Int],
        at _: PerformanceMonotonicInstant
    ) -> StepAttemptMatchResult {
        .insufficientEvidence
    }

    func reset() {}
}
