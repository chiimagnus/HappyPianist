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
    firstSession.setSteps(
        [PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1, handAssignment: .unknown)])],
        measureSpans: [span]
    )
    firstSession.roundConfigurationController.pendingRequiredSuccesses = 1
    _ = firstSession.applyPendingRoundConfiguration()
    await firstSession.applyLaunchRestorePolicy(.freshDefaults)
    firstSession.startGuidingIfReady()
    firstSession.recordAttemptOutcome(matchedLearningLoopOutcome())
    await firstSession.flushAndShutdown()

    let saved = try #require(await repository.progress(for: identity))
    #expect(saved.measureFacts.first?.state == .stable)
    #expect(saved.resumePoint?.stepIndex == 0)

    let secondCoordinator = PracticeProgressCoordinator(repository: repository, checkpointDelay: .seconds(60))
    let secondPlayback = LearningLoopPlaybackService()
    let secondSession = makeLearningLoopSession(
        playback: secondPlayback,
        coordinator: secondCoordinator
    )
    secondSession.songIdentity = identity
    secondSession.setSteps(
        [PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1, handAssignment: .unknown)])],
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
private func makeLearningLoopSession(
    playback: LearningLoopPlaybackService,
    coordinator: PracticeProgressCoordinator
) -> PracticeSessionViewModel {
    PracticeSessionViewModel(
        pressDetectionService: LearningLoopPressDetector(),
        chordAttemptAccumulator: LearningLoopChordAccumulator(),
        sleeper: TaskSleeper(),
        sequencerPlaybackService: playback,
        progressCoordinator: coordinator
    )
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
    func stop() {}
    func load(sequence _: PracticeSequencerSequence) throws {}
    func play(fromSeconds _: TimeInterval) throws {
        playCount += 1
    }

    func currentSeconds() -> TimeInterval {
        0
    }

    func playOneShot(noteOns _: [PracticeOneShotNoteOn], durationSeconds _: TimeInterval) throws {
        oneShotCount += 1
    }

    func startLiveNotes(midiNotes _: Set<Int>) throws {}
    func stopLiveNotes(midiNotes _: Set<Int>) {}
    func stopAllLiveNotes() {}
}

private struct LearningLoopPressDetector: PressDetectionServiceProtocol {
    func detectPressedNotes(
        fingerTips _: FingerTipsSnapshot,
        keyboardGeometry _: PianoKeyboardGeometry?,
        at _: Date
    ) -> Set<Int> {
        []
    }
}

private final class LearningLoopChordAccumulator: ChordAttemptAccumulatorProtocol {
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
