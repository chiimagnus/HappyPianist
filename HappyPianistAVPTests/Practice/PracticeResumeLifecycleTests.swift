import Foundation
@testable import HappyPianistAVP
import Testing

@MainActor
@Test
func restoredPracticeStaysReadyAndSilentUntilExplicitStart() async throws {
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "r1")
    let spans = makeResumeSpans()
    let passage = try #require(PracticePassage(start: spans[0].occurrenceID, end: spans[1].occurrenceID))
    let configuration = PracticeRoundConfiguration(
        passage: passage,
        handMode: .right,
        tempoScale: 0.7,
        loopEnabled: true,
        requiredSuccesses: 3
    )
    let progress = SongPracticeProgress(
        identity: identity,
        activeConfiguration: configuration,
        resumePoint: PracticeResumePoint(
            occurrenceID: spans[1].occurrenceID,
            stepIndex: 1,
            updatedAt: .now
        ),
        updatedAt: .now
    )
    let repository = ResumeRepository(progress: progress)
    let coordinator = PracticeProgressCoordinator(repository: repository, checkpointDelay: .seconds(60))
    let playback = CapturingResumePlaybackService()
    let session = PracticeSessionViewModel(
        chordAttemptAccumulator: ResumeNoopChordAccumulator(),
        sleeper: TaskSleeper(),
        sequencerPlaybackService: playback,
        progressCoordinator: coordinator
    )
    session.songIdentity = identity
    session.installTestPerformanceNotes(makeResumePerformanceNotes(), measureSpans: spans)

    await session.applyLaunchRestorePolicy(.exactAvailable)

    #expect(session.state == .ready)
    #expect(session.currentStepIndex == 1)
    #expect(session.notationViewportTick() == Double(makeResumePerformanceNotes()[1].onTick))
    #expect(session.activeRoundConfiguration == configuration)
    #expect(session.isRestoredSessionPaused)
    #expect(playback.oneShotCount == 0)
    #expect(playback.playCount == 0)

    session.startGuidingIfReady()
    await playback.waitForOneShot()
    #expect(session.state == .guiding(stepIndex: 1))
    #expect(playback.oneShotCount == 1)
}

@MainActor
@Test
func exactProgressAppearingAfterHistoricalPolicySnapshotStillWins() async throws {
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "r1")
    let spans = makeResumeSpans()
    let passage = try #require(PracticePassage(start: spans[1].occurrenceID, end: spans[1].occurrenceID))
    let exactConfiguration = PracticeRoundConfiguration(
        passage: passage,
        handMode: .left,
        tempoScale: 0.8,
        loopEnabled: true,
        requiredSuccesses: 4
    )
    let progress = SongPracticeProgress(
        identity: identity,
        activeConfiguration: exactConfiguration,
        resumePoint: PracticeResumePoint(
            occurrenceID: spans[1].occurrenceID,
            stepIndex: 1,
            updatedAt: .now
        ),
        updatedAt: .now
    )
    let repository = ResumeRepository(progress: progress)
    let session = PracticeSessionViewModel(
        chordAttemptAccumulator: ResumeNoopChordAccumulator(),
        sleeper: TaskSleeper(),
        progressCoordinator: PracticeProgressCoordinator(repository: repository)
    )
    session.songIdentity = identity
    session.installTestPerformanceNotes(makeResumePerformanceNotes(), measureSpans: spans)

    await session.applyLaunchRestorePolicy(.historicalPreferences(
        PracticeHistoricalPreferences(
            handMode: .right,
            tempoScale: 0.5,
            loopEnabled: false,
            requiredSuccesses: 1
        )
    ))

    #expect(session.activeRoundConfiguration == exactConfiguration)
    #expect(session.currentStepIndex == 1)
    #expect(session.sessionProgress == progress)
    #expect(session.lastProgressRestoreOutcome == .restored)
}

@MainActor
@Test
func invalidRestoredPassageIsRepairedAndPersistedWithoutLosingFacts() async throws {
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "r1")
    let spans = makeResumeSpans()
    let missingSource = PracticeSourceMeasureID(partID: "P1", sourceMeasureIndex: 99)
    let missingOccurrence = PracticeMeasureOccurrenceID(sourceMeasureID: missingSource, occurrenceIndex: 99)
    let passage = try #require(PracticePassage(start: missingOccurrence, end: missingOccurrence))
    let retainedFact = MeasurePracticeFacts(
        sourceMeasureID: spans[0].occurrenceID.sourceMeasureID,
        handMode: .both,
        state: .learning,
        successfulAttempts: 1
    )
    let progress = SongPracticeProgress(
        identity: identity,
        activeConfiguration: PracticeRoundConfiguration(
            passage: passage,
            handMode: .both,
            tempoScale: 1,
            loopEnabled: false,
            requiredSuccesses: 3
        ),
        resumePoint: PracticeResumePoint(
            occurrenceID: missingOccurrence,
            stepIndex: 99,
            updatedAt: .now
        ),
        measureFacts: [retainedFact],
        updatedAt: .now
    )
    let repository = ResumeRepository(progress: progress)
    let playback = CapturingResumePlaybackService()
    let session = PracticeSessionViewModel(
        chordAttemptAccumulator: ResumeNoopChordAccumulator(),
        sleeper: TaskSleeper(),
        sequencerPlaybackService: playback,
        progressCoordinator: PracticeProgressCoordinator(repository: repository)
    )
    session.songIdentity = identity
    session.installTestPerformanceNotes(makeResumePerformanceNotes(), measureSpans: spans)

    await session.applyLaunchRestorePolicy(.exactAvailable)
    let repaired = try #require(await repository.progress(for: identity))
    let repairedConfiguration = try #require(repaired.activeConfiguration)

    #expect(session.activeRangeDiagnostic == nil)
    #expect(session.state == .ready)
    #expect(session.currentStepIndex == 0)
    #expect(repairedConfiguration.passage.start == spans.first?.occurrenceID)
    #expect(repairedConfiguration.passage.end == spans.last?.occurrenceID)
    #expect(repaired.resumePoint == nil)
    #expect(repaired.measureFacts == [retainedFact])
    #expect(session.lastProgressRestoreOutcome == .repairedInvalidSavedState)
}

@MainActor
@Test
func invalidRestoredPassageUsesSafeFallbackWhenRepairCannotPersist() async throws {
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "r1")
    let spans = makeResumeSpans()
    let missingOccurrence = PracticeMeasureOccurrenceID(
        sourceMeasureID: PracticeSourceMeasureID(partID: "P1", sourceMeasureIndex: 99),
        occurrenceIndex: 99
    )
    let invalidPassage = try #require(
        PracticePassage(start: missingOccurrence, end: missingOccurrence)
    )
    let storedProgress = SongPracticeProgress(
        identity: identity,
        activeConfiguration: PracticeRoundConfiguration(
            passage: invalidPassage,
            handMode: .left,
            tempoScale: 0.7,
            loopEnabled: true,
            requiredSuccesses: 4
        ),
        updatedAt: .now
    )
    let repository = FailingRepairRepository(progress: storedProgress)
    let session = PracticeSessionViewModel(
        chordAttemptAccumulator: ResumeNoopChordAccumulator(),
        sleeper: TaskSleeper(),
        progressCoordinator: PracticeProgressCoordinator(repository: repository)
    )
    session.songIdentity = identity
    session.installTestPerformanceNotes(
        makeResumePerformanceNotes(),
        measureSpans: spans
    )

    await session.applyLaunchRestorePolicy(.exactAvailable)

    #expect(session.activeRangeDiagnostic == nil)
    #expect(session.activeRoundConfiguration?.passage.start == spans.first?.occurrenceID)
    #expect(session.activeRoundConfiguration?.passage.end == spans.last?.occurrenceID)
    #expect(session.lastProgressRestoreOutcome == .repairPersistenceFailed)
    #expect(await repository.progress(for: identity)?.activeConfiguration == storedProgress.activeConfiguration)
}

@MainActor
@Test
func resumeOutsideValidActivePassageIsClearedAndPersistedWithoutLosingFacts() async throws {
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "r1")
    let spans = makeResumeSpans()
    let passage = try #require(PracticePassage(
        start: spans[0].occurrenceID,
        end: spans[0].occurrenceID
    ))
    let retainedFact = MeasurePracticeFacts(
        sourceMeasureID: spans[0].occurrenceID.sourceMeasureID,
        handMode: .both,
        state: .learning,
        successfulAttempts: 1
    )
    let storedProgress = SongPracticeProgress(
        identity: identity,
        activeConfiguration: PracticeRoundConfiguration(
            passage: passage,
            handMode: .both,
            tempoScale: 1,
            loopEnabled: false,
            requiredSuccesses: 3
        ),
        resumePoint: PracticeResumePoint(
            occurrenceID: spans[1].occurrenceID,
            stepIndex: 1,
            updatedAt: .now
        ),
        measureFacts: [retainedFact],
        updatedAt: .now
    )
    let repository = ResumeRepository(progress: storedProgress)
    let session = PracticeSessionViewModel(
        chordAttemptAccumulator: ResumeNoopChordAccumulator(),
        sleeper: TaskSleeper(),
        progressCoordinator: PracticeProgressCoordinator(repository: repository)
    )
    session.songIdentity = identity
    session.installTestPerformanceNotes(
        makeResumePerformanceNotes(),
        measureSpans: spans
    )

    await session.applyLaunchRestorePolicy(.exactAvailable)

    let repaired = try #require(await repository.progress(for: identity))
    #expect(repaired.activeConfiguration == storedProgress.activeConfiguration)
    #expect(repaired.resumePoint == nil)
    #expect(repaired.measureFacts == [retainedFact])
    #expect(session.currentStepIndex == 0)
    #expect(session.lastProgressRestoreOutcome == .repairedInvalidSavedState)
}

@MainActor
@Test
func resumeWithoutSavedConfigurationIsClearedAndRepairedToFullPassage() async throws {
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "r1")
    let spans = makeResumeSpans()
    let retainedFact = MeasurePracticeFacts(
        sourceMeasureID: spans[0].occurrenceID.sourceMeasureID,
        handMode: .both,
        state: .learning,
        successfulAttempts: 1
    )
    let storedProgress = SongPracticeProgress(
        identity: identity,
        resumePoint: PracticeResumePoint(
            occurrenceID: spans[1].occurrenceID,
            stepIndex: 1,
            updatedAt: .now
        ),
        measureFacts: [retainedFact],
        updatedAt: .now
    )
    let repository = ResumeRepository(progress: storedProgress)
    let session = PracticeSessionViewModel(
        chordAttemptAccumulator: ResumeNoopChordAccumulator(),
        sleeper: TaskSleeper(),
        progressCoordinator: PracticeProgressCoordinator(repository: repository)
    )
    session.songIdentity = identity
    session.installTestPerformanceNotes(
        makeResumePerformanceNotes(),
        measureSpans: spans
    )

    await session.applyLaunchRestorePolicy(.exactAvailable)

    let repaired = try #require(await repository.progress(for: identity))
    #expect(repaired.activeConfiguration?.passage.start == spans.first?.occurrenceID)
    #expect(repaired.activeConfiguration?.passage.end == spans.last?.occurrenceID)
    #expect(repaired.resumePoint == nil)
    #expect(repaired.measureFacts == [retainedFact])
    #expect(session.currentStepIndex == 0)
    #expect(session.lastProgressRestoreOutcome == .repairedInvalidSavedState)
}

@MainActor
@Test
func suspendedPracticeReturnsToPausedReadyAndCanRestartInput() async {
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "r1")
    let repository = ResumeRepository(progress: nil)
    let coordinator = PracticeProgressCoordinator(repository: repository, checkpointDelay: .seconds(60))
    let session = PracticeSessionViewModel(
        chordAttemptAccumulator: ResumeNoopChordAccumulator(),
        sleeper: TaskSleeper(),
        progressCoordinator: coordinator
    )
    session.songIdentity = identity
    session.installTestPerformanceNotes(
        makeResumePerformanceNotes(),
        measureSpans: makeResumeSpans()
    )
    await session.applyLaunchRestorePolicy(.freshDefaults)
    session.startGuidingIfReady()
    session.latestFeedbackEvent = PracticeFeedbackEvent(
        sequence: 1,
        sourceMeasureID: makeResumeSpans()[0].occurrenceID.sourceMeasureID,
        kind: .retryInvitation(issue: .wrongNote)
    )
    await session.suspendAndFlushProgress()

    #expect(session.acceptsPracticeAttempts == false)
    #expect(session.latestFeedbackEvent == nil)
    session.resumeAfterSuspension()
    #expect(session.acceptsPracticeAttempts)
    #expect(session.state == .ready)
    #expect(session.isRestoredSessionPaused)
}

@MainActor
@Test
func pausedPracticeRejectsAdvanceEffectWithoutPlayback() {
    let playback = CapturingResumePlaybackService()
    let session = PracticeSessionViewModel(
        chordAttemptAccumulator: ResumeNoopChordAccumulator(),
        sleeper: TaskSleeper(),
        sequencerPlaybackService: playback
    )
    session.installTestPerformanceNotes(makeResumePerformanceNotes(), measureSpans: makeResumeSpans())

    session.handle(effect: .advanceToNextStep)

    #expect(session.state == .ready)
    #expect(session.currentStepIndex == 0)
    #expect(playback.oneShotCount == 0)
    #expect(playback.playCount == 0)
}

@MainActor
@Test
func flushAndShutdownPersistsLatestResumePointBeforeTeardown() async {
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "r1")
    let repository = ResumeRepository(progress: nil)
    let coordinator = PracticeProgressCoordinator(repository: repository, checkpointDelay: .seconds(60))
    let session = PracticeSessionViewModel(
        chordAttemptAccumulator: ResumeNoopChordAccumulator(),
        sleeper: TaskSleeper(),
        progressCoordinator: coordinator
    )
    let spans = makeResumeSpans()
    session.songIdentity = identity
    session.installTestPerformanceNotes(makeResumePerformanceNotes(), measureSpans: spans)
    await session.applyLaunchRestorePolicy(.freshDefaults)
    session.startGuidingIfReady()
    session.recordAttemptOutcome(
        .matched
    )

    await session.flushAndShutdown()

    #expect(await repository.progress(for: identity)?.resumePoint?.stepIndex == 0)
    #expect(session.acceptsPracticeAttempts == false)
}

@MainActor
@Test
func navigationWithoutAttemptPersistsLatestResumePoint() async {
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "r1")
    let repository = ResumeRepository(progress: nil)
    let session = PracticeSessionViewModel(
        chordAttemptAccumulator: ResumeNoopChordAccumulator(),
        sleeper: TaskSleeper(),
        progressCoordinator: PracticeProgressCoordinator(repository: repository, checkpointDelay: .seconds(60))
    )
    let spans = makeResumeSpans()
    session.songIdentity = identity
    session.installTestPerformanceNotes(makeResumePerformanceNotes(), measureSpans: spans)
    await session.applyLaunchRestorePolicy(.freshDefaults)
    session.startGuidingIfReady()

    session.moveToStep(1, shouldPlaySound: false)
    await session.flushAndShutdown()

    #expect(await repository.progress(for: identity)?.resumePoint?.stepIndex == 1)
    #expect(await repository.progress(for: identity)?.resumePoint?.occurrenceID == spans[1].occurrenceID)
}

@MainActor
@Test
func retryMeasureKeepsRepeatedOccurrenceInCurrentPassage() {
    let repeatedSource = PracticeSourceMeasureID(partID: "P1", sourceMeasureIndex: 0, sourceNumberToken: "1")
    let spans = [
        MusicXMLMeasureSpan(partID: "P1", measureNumber: 1, sourceMeasureIndex: 0, sourceMeasureNumberToken: "1", occurrenceIndex: 0, startTick: 0, endTick: 480),
        MusicXMLMeasureSpan(partID: "P1", measureNumber: 2, sourceMeasureIndex: 1, sourceMeasureNumberToken: "2", occurrenceIndex: 1, startTick: 480, endTick: 960),
        MusicXMLMeasureSpan(partID: "P1", measureNumber: 3, sourceMeasureIndex: 0, sourceMeasureNumberToken: "1", occurrenceIndex: 2, startTick: 960, endTick: 1440),
    ]
    let session = PracticeSessionViewModel(
        chordAttemptAccumulator: ResumeNoopChordAccumulator(),
        sleeper: TaskSleeper()
    )
    session.installTestPerformanceNotes(
        [
            TestScorePerformanceNote(midiNote: 60, onTick: 0),
            TestScorePerformanceNote(midiNote: 62, onTick: 480),
            TestScorePerformanceNote(midiNote: 60, onTick: 960),
        ],
        measureSpans: spans
    )
    session.roundConfigurationController.pendingPassage = PracticePassage(
        start: spans[2].occurrenceID,
        end: spans[2].occurrenceID
    )
    _ = session.applyPendingRoundConfiguration()

    session.retryMeasure(repeatedSource)

    #expect(session.activeRoundConfiguration?.passage.start == spans[2].occurrenceID)
    #expect(session.activeRoundConfiguration?.passage.start.sourceMeasureID == repeatedSource)
}

@MainActor
@Test
func automaticLoopStartsANewAttemptRound() {
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "r1")
    let span = makeResumeSpans()[0]
    let session = PracticeSessionViewModel(
        chordAttemptAccumulator: ResumeNoopChordAccumulator(),
        sleeper: TaskSleeper()
    )
    session.songIdentity = identity
    session.installTestPerformanceNotes(
        [TestScorePerformanceNote(midiNote: 60, onTick: 0)],
        measureSpans: [span]
    )
    session.roundConfigurationController.pendingLoopEnabled = true
    _ = session.applyPendingRoundConfiguration()
    session.startGuidingIfReady()
    let firstGeneration = session.roundGeneration
    let wrong = StepAttemptMatchResult.wrongNote

    session.recordAttemptOutcome(wrong)
    session.advanceToNextStep()
    let secondGeneration = session.roundGeneration
    session.recordAttemptOutcome(wrong)

    #expect(secondGeneration == firstGeneration + 1)
    #expect(session.sessionProgress?.measureFacts.first?.failedAttempts == 2)
}

@MainActor
@Test
func automaticLoopStopsWhenPassageReachesTarget() {
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "r1")
    let span = makeResumeSpans()[0]
    let session = PracticeSessionViewModel(
        chordAttemptAccumulator: ResumeNoopChordAccumulator(),
        sleeper: TaskSleeper()
    )
    session.songIdentity = identity
    session.installTestPerformanceNotes(
        [TestScorePerformanceNote(midiNote: 60, onTick: 0)],
        measureSpans: [span]
    )
    session.roundConfigurationController.pendingLoopEnabled = true
    session.roundConfigurationController.pendingRequiredSuccesses = 1
    _ = session.applyPendingRoundConfiguration()
    session.startGuidingIfReady()
    let generation = session.roundGeneration
    session.recordAttemptOutcome(.matched)

    session.advanceToNextStep()

    #expect(session.state == .completed)
    #expect(session.roundGeneration == generation)
    #expect(session.latestFeedbackEvent?.kind == .passageStable)
}

@MainActor
@Test
func continuePassageStartsANewRoundInPractice() {
    let span = makeResumeSpans()[0]
    let session = PracticeSessionViewModel(
        chordAttemptAccumulator: ResumeNoopChordAccumulator(),
        sleeper: TaskSleeper()
    )
    session.installTestPerformanceNotes(
        [TestScorePerformanceNote(midiNote: 60, onTick: 0)],
        measureSpans: [span]
    )
    session.startGuidingIfReady()
    session.advanceToNextStep()
    let completedGeneration = session.roundGeneration

    #expect(session.perform(.continuePassage))
    #expect(session.roundGeneration == completedGeneration + 1)
    #expect(session.state == .guiding(stepIndex: 0))
    #expect(session.currentStepIndex == 0)
}

private func makeResumePerformanceNotes() -> [TestScorePerformanceNote] {
    let rightHand = ScoreHandAssignment(hand: .right, provenance: .score)
    return [
        TestScorePerformanceNote(midiNote: 60, onTick: 0, handAssignment: rightHand),
        TestScorePerformanceNote(midiNote: 62, onTick: 480, handAssignment: rightHand),
    ]
}

private func makeResumeSpans() -> [MusicXMLMeasureSpan] {
    [
        MusicXMLMeasureSpan(partID: "P1", measureNumber: 1, sourceMeasureIndex: 0, sourceMeasureNumberToken: "1", occurrenceIndex: 0, startTick: 0, endTick: 480),
        MusicXMLMeasureSpan(partID: "P1", measureNumber: 2, sourceMeasureIndex: 1, sourceMeasureNumberToken: "2", occurrenceIndex: 1, startTick: 480, endTick: 960),
    ]
}

private actor ResumeRepository: PracticeProgressRepositoryProtocol {
    private var stored: SongPracticeProgress?

    init(progress: SongPracticeProgress?) {
        stored = progress
    }

    func load() -> PracticeProgressLoadResult {
        .loaded(PracticeProgressDocument(songs: stored.map { [$0] } ?? []))
    }

    func progress(for identity: PracticeSongIdentity) -> SongPracticeProgress? {
        stored?.identity == identity ? stored : nil
    }

    func history(for songID: UUID) -> PracticeSongHistoryLoadResult {
        .loaded(PracticeSongHistory(
            songID: songID,
            progresses: stored.map { $0.identity.songID == songID ? [$0] : [] } ?? [],
            scoreMetadata: [],
            sessions: []
        ))
    }

    func upsert(_ progress: SongPracticeProgress) {
        stored = progress
    }

    func upsert(_: SongScorePracticeMetadata) {}

    func remove(songID: UUID) {
        if stored?.identity.songID == songID { stored = nil }
    }
}

private actor FailingRepairRepository: PracticeProgressRepositoryProtocol {
    let stored: SongPracticeProgress

    init(progress: SongPracticeProgress) {
        stored = progress
    }

    func load() -> PracticeProgressLoadResult {
        .loaded(PracticeProgressDocument(songs: [stored]))
    }

    func progress(for identity: PracticeSongIdentity) -> SongPracticeProgress? {
        stored.identity == identity ? stored : nil
    }

    func history(for songID: UUID) -> PracticeSongHistoryLoadResult {
        .loaded(PracticeSongHistory(
            songID: songID,
            progresses: stored.identity.songID == songID ? [stored] : [],
            scoreMetadata: [],
            sessions: []
        ))
    }

    func upsert(_: SongPracticeProgress) throws {
        throw CocoaError(.fileWriteOutOfSpace)
    }

    func upsert(_: SongScorePracticeMetadata) throws {
        throw CocoaError(.fileWriteOutOfSpace)
    }

    func remove(songID _: UUID) {}
}

private final class CapturingResumePlaybackService: PracticeSequencerPlaybackServiceProtocol {
    private(set) var oneShotCount = 0
    private(set) var playCount = 0
    private let oneShotEvents: AsyncStream<Void>
    private let oneShotContinuation: AsyncStream<Void>.Continuation

    init() {
        (oneShotEvents, oneShotContinuation) = AsyncStream.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
    }

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
        oneShotContinuation.yield()
    }

    func waitForOneShot() async {
        var iterator = oneShotEvents.makeAsyncIterator()
        _ = await iterator.next()
    }

    func execute(commands _: [PracticePlaybackCommand]) throws {}
    func stopAllLiveNotes() {}
}

private final class ResumeNoopChordAccumulator: ChordAttemptAccumulatorProtocol {
    func register(
        pressedNotes _: Set<Int>,
        expectedNotes _: [Int],
        at _: PerformanceMonotonicInstant
    ) -> StepAttemptMatchResult {
        .insufficientEvidence
    }

    func reset() {}
}
