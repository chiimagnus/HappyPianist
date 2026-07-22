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
func sessionShutdownResetsPerformanceAnalysis() async throws {
    let analyzer = PracticePerformanceAnalyzer()
    let recorder = PracticeSessionRecorder(
        repository: LearningLoopSessionRepository(),
        performanceAnalyzer: analyzer
    )
    let session = makeLearningLoopSession(
        playback: LearningLoopPlaybackService(),
        coordinator: PracticeProgressCoordinator(repository: LearningLoopRepository()),
        recorder: recorder
    )
    session.installTestPerformanceNotes([
        TestScorePerformanceNote(midiNote: 60, onTick: 0, offTick: 480),
    ])
    await session.waitForSessionRecorderEvents()
    let instant = PerformanceClock.live().now()
    await analyzer.record(PerformanceObservation(
        source: .init(kind: .midi1, id: "midi:shutdown", generation: 1),
        timing: .init(
            host: instant,
            source: nil,
            correctedHost: instant,
            mapping: nil,
            provenance: .hostOnly
        ),
        event: .noteOn(note: 60, velocity: .init(midi1: 90))
    ))
    #expect(await analyzer.snapshot().isRunning)

    session.shutdown()
    await session.waitForSessionRecorderEvents()

    let reset = await analyzer.snapshot()
    #expect(reset.isRunning == false)
    #expect(reset.acceptedObservationCount == 0)
    #expect(reset.alignment == nil)
}

@MainActor
@Test
func completedPassagePersistsAssessmentOnceAndFinishesAnalyzerRound() async throws {
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "assessment-r1")
    let diagnosticsReporter = InMemoryDiagnosticsReporter()
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
        recorder: recorder,
        diagnosticsReporter: diagnosticsReporter
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
    await recorder.record(PerformanceObservation(
        source: .init(kind: .midi1, id: "midi:integration", generation: 1),
        timing: .init(
            host: instant,
            source: nil,
            correctedHost: instant,
            mapping: nil,
            provenance: .hostOnly
        ),
        event: .noteOn(note: 61, velocity: .init(midi1: 90))
    ))
    session.recordAttemptOutcome(matchedLearningLoopOutcome())
    session.advanceToNextStep()
    await session.waitForSessionRecorderEvents()

    let firstSummary = try #require(session.sessionProgress?.measureFacts.first?.performanceMaturity)
    #expect(firstSummary.metricSummaries.contains { $0.dimension == .exactPitch })
    let decision = try #require(session.currentCoachingDecision)
    #expect(decision.issue.kind == .evidence)
    #expect(decision.action.kind == .evidenceCheck)
    #expect(session.latestFeedbackEvent?.kind == .roundSummaryReady)
    #expect(await recorder.analysisSnapshot().isRunning == false)

    let issuedEvent = try #require(await diagnosticsReporter.events.first {
        $0.stage == PianoPerformanceDiagnosticStage.coaching.rawValue
            && $0.reason.contains("outcome=issued")
    })
    let decisionID = try #require(issuedEvent.operationID)
    #expect(issuedEvent.persistence == .systemOnly)
    #expect(issuedEvent.reason.contains("action=evidenceCheck"))
    #expect(issuedEvent.reason.contains("beforeDimension="))
    #expect(issuedEvent.reason.contains("note=") == false)

    #expect(session.perform(.retryMeasure(learningLoopSpan().occurrenceID.sourceMeasureID)))
    await session.waitForSessionRecorderEvents()
    let acceptedEvents = await diagnosticsReporter.events.filter { $0.operationID == decisionID }
    #expect(acceptedEvents.contains { $0.reason.contains("outcome=accepted") })
    #expect(acceptedEvents.contains { $0.reason.contains("outcome=remeasured") } == false)

    let retryInstant = PerformanceClock.live().now()
    await recorder.record(PerformanceObservation(
        source: .init(kind: .midi1, id: "midi:integration", generation: 1),
        timing: .init(
            host: retryInstant,
            source: nil,
            correctedHost: retryInstant,
            mapping: nil,
            provenance: .hostOnly
        ),
        event: .noteOn(note: 60, velocity: .init(midi1: 90))
    ))
    let releaseInstant = retryInstant.advanced(by: 0.5)
    await recorder.record(PerformanceObservation(
        source: .init(kind: .midi1, id: "midi:integration", generation: 1),
        timing: .init(
            host: releaseInstant,
            source: nil,
            correctedHost: releaseInstant,
            mapping: nil,
            provenance: .hostOnly
        ),
        event: .noteOff(note: 60, releaseVelocity: .init(midi1: 32))
    ))
    session.recordAttemptOutcome(matchedLearningLoopOutcome())
    session.advanceToNextStep()
    await session.waitForSessionRecorderEvents()

    let remeasuredEvent = try #require(await diagnosticsReporter.events.first {
        $0.operationID == decisionID && $0.reason.contains("outcome=remeasured")
    })
    #expect(remeasuredEvent.reason.contains("afterDimension="))
    #expect(remeasuredEvent.reason.contains("after=unavailable") == false)
    let remeasuredSummary = try #require(
        session.sessionProgress?.measureFacts.first?.performanceMaturity
    )
    #expect(remeasuredSummary != firstSummary)

    session.recordPassageCompletion()
    await session.waitForSessionRecorderEvents()
    #expect(session.sessionProgress?.measureFacts.first?.performanceMaturity == remeasuredSummary)

    #expect(await session.flushProgress() == .saved)
    let saved = try #require(await progressRepository.progress(for: identity))
    #expect(saved.measureFacts.first?.performanceMaturity == remeasuredSummary)

    #expect(session.currentCoachingDecision != nil)
    let followupIssuedEvent = try #require(await diagnosticsReporter.events.last {
        $0.operationID != decisionID && $0.reason.contains("outcome=issued")
    })
    session.skipCoachingDecisionAndContinue()
    await session.waitForSessionRecorderEvents()
    #expect(await diagnosticsReporter.events.contains {
        $0.operationID == followupIssuedEvent.operationID
            && $0.reason.contains("outcome=skipped")
    })
    #expect(session.state == .guiding(stepIndex: 0))
    #expect(session.currentCoachingDecision == nil)
}

@MainActor
@Test
func passageCompletionDrainsTheLastMIDIObservationBeforeAssessment() async throws {
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "drain-r1")
    let inputSource = FakeProtocolSeparatedPracticeInputEventSource()
    let recorder = PracticeSessionRecorder(
        repository: LearningLoopSessionRepository(),
        performanceAnalyzer: PracticePerformanceAnalyzer()
    )
    await recorder.beginVisit(id: UUID(), songID: identity.songID, sceneIsActive: true)
    await recorder.bindIdentity(identity)
    let session = makeLearningLoopSession(
        playback: LearningLoopPlaybackService(),
        coordinator: PracticeProgressCoordinator(repository: LearningLoopRepository()),
        recorder: recorder,
        practiceInputEventSource: inputSource
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

    inputSource.emitMIDI1(MIDI1InputEvent(
        kind: .noteOn(note: 60, velocity: 100),
        channel: 1,
        group: 0,
        source: .init(identifier: .sourceIndex(0), endpointName: "test"),
        receivedAt: .now,
        receivedAtUptimeSeconds: ProcessInfo.processInfo.systemUptime
    ))
    for _ in 0 ..< 100 {
        if await recorder.analysisSnapshot().isRunning == false { break }
        await Task.yield()
    }
    await session.waitForSessionRecorderEvents()

    let snapshot = await recorder.analysisSnapshot()
    let pitch = try #require(snapshot.assessment?.dimensions.first { $0.dimension == .exactPitch })
    #expect(snapshot.acceptedObservationCount == 1)
    #expect(pitch.outcome == .correct)
}

@MainActor
@Test
func realPianoContactFlowsIntoTheSessionAssessment() async throws {
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "hand-r1")
    let recorder = PracticeSessionRecorder(
        repository: LearningLoopSessionRepository(),
        performanceAnalyzer: PracticePerformanceAnalyzer()
    )
    await recorder.beginVisit(id: UUID(), songID: identity.songID, sceneIsActive: true)
    await recorder.bindIdentity(identity)
    let session = makeLearningLoopSession(
        playback: LearningLoopPlaybackService(),
        coordinator: PracticeProgressCoordinator(repository: LearningLoopRepository()),
        recorder: recorder,
        handObservationSourceKind: .realPianoContact
    )
    session.songIdentity = identity
    session.installTestPerformanceNotes(
        [TestScorePerformanceNote(midiNote: 60, onTick: 0, offTick: 480)],
        measureSpans: [learningLoopSpan()]
    )
    await session.applyLaunchRestorePolicy(.freshDefaults)
    session.startGuidingIfReady()
    await session.waitForSessionRecorderEvents()

    let calibrationID = UUID()
    session.recordHandPerformanceObservations([makeTestKeyContactObservation(
        midiNote: 60,
        phase: .started,
        timestamp: PerformanceClock.live().now(),
        resolvedVelocity: 73,
        calibrationID: calibrationID
    )])
    session.recordPassageCompletion()
    await session.waitForSessionRecorderEvents()

    let snapshot = await recorder.analysisSnapshot()
    let assessment = try #require(snapshot.assessment)
    let pitch = try #require(assessment.dimensions.first { $0.dimension == .exactPitch })
    #expect(snapshot.acceptedObservationCount == 1)
    #expect(pitch.outcome == .correct)
    #expect(pitch.evidence.contains { evidence in
        guard case let .note(_, observationID, _) = evidence else { return false }
        return snapshot.alignment?.links.contains { link in
            guard case let .aligned(_, observation, _) = link else { return false }
            return observation.observationID == observationID
                && observation.hand == .right
                && observation.finger == 2
                && observation.calibrationReference == calibrationID.uuidString
        } == true
    })
}

@MainActor
@Test
func performingCoachingActionPracticesTheDiagnosedMeasureAtTheRequestedTempo() throws {
    let session = makeLearningLoopSession(
        playback: LearningLoopPlaybackService(),
        coordinator: PracticeProgressCoordinator(repository: LearningLoopRepository())
    )
    let firstSpan = learningLoopSpan()
    let secondSpan = MusicXMLMeasureSpan(
        partID: "P1",
        measureNumber: 2,
        sourceMeasureIndex: 1,
        sourceMeasureNumberToken: "2",
        occurrenceIndex: 0,
        startTick: 480,
        endTick: 960
    )
    session.installTestPerformanceNotes([
        TestScorePerformanceNote(midiNote: 60, onTick: 0, offTick: 480),
        TestScorePerformanceNote(midiNote: 62, onTick: 480, offTick: 960),
    ], measureSpans: [firstSpan, secondSpan])
    let dimension = PerformanceAssessmentDimensionResult(
        dimension: .onset,
        outcome: .incorrect,
        evidenceStatus: .observed,
        sampleCount: 2,
        confidence: 0.9,
        evidence: []
    )
    let issue = MusicalIssue(
        kind: .onset,
        scoreRange: 480 ..< 960,
        measureOccurrenceIDs: [secondSpan.occurrenceID],
        dimensionResults: [dimension],
        confidence: 0.9,
        provenance: MusicalIssueProvenance(
            planID: try #require(session.performancePlan).id,
            sourceGeneration: 1,
            rubricVersion: .capabilityAware
        )
    )
    session.currentCoachingDecision = CoachingDecision(
        issue: issue,
        action: CoachingAction(
            kind: .onsetAlignment,
            scoreRange: issue.scoreRange,
            tempoRatio: 0.7,
            repeatCount: 2,
            completionCondition: CoachingCompletionCondition(
                target: .dimensionOutcome(dimension: .onset, outcome: .correct)
            )
        )
    )

    #expect(session.perform(.lowerTempo(0.7)))

    #expect(session.activeRoundConfiguration?.passage == PracticePassage(
        start: secondSpan.occurrenceID,
        end: secondSpan.occurrenceID
    ))
    #expect(session.activeRoundConfiguration?.tempoScale == 0.7)
    #expect(session.activeRange?.measureSpans == [secondSpan])
    #expect(session.state == .guiding(stepIndex: 1))
}

@MainActor
private func makeLearningLoopSession(
    playback: LearningLoopPlaybackService,
    coordinator: PracticeProgressCoordinator,
    recorder: PracticeSessionRecorder? = nil,
    practiceInputEventSource: PracticeInputEventSourceProtocol? = nil,
    handObservationSourceKind: PerformanceObservation.Source.Kind? = nil,
    diagnosticsReporter: (any DiagnosticsReporting)? = nil
) -> PracticeSessionViewModel {
    PracticeSessionViewModel(
        chordAttemptAccumulator: LearningLoopChordAccumulator(),
        sleeper: TaskSleeper(),
        sequencerPlaybackService: playback,
        handObservationSourceKind: handObservationSourceKind,
        practiceInputEventSource: practiceInputEventSource,
        progressCoordinator: coordinator,
        sessionRecorder: recorder,
        diagnosticsReporter: diagnosticsReporter
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
