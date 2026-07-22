import Foundation
@testable import HappyPianistAVP
import Testing

@Test
func feedbackPolicyPublishesTypedRetryAndRejectsMissingFact() {
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "r1")
    let source = PracticeSourceMeasureID(partID: "P1", sourceMeasureIndex: 1)
    let progress = SongPracticeProgress(identity: identity, updatedAt: .now)

    let events = PracticeFeedbackPolicy().events(
        for: .attemptIssue(sourceMeasureID: source, issue: .wrongNote),
        previousProgress: nil,
        progress: progress,
        eventSequence: 1,
        passageSourceMeasureIDs: [source]
    )

    #expect(events == [PracticeFeedbackEvent(
        sequence: 1,
        sourceMeasureID: source,
        kind: .retryInvitation(issue: .wrongNote)
    )])
    #expect(PracticeFeedbackPolicy().events(
        for: nil,
        previousProgress: nil,
        progress: progress,
        eventSequence: 2,
        passageSourceMeasureIDs: [source]
    ).isEmpty)
}

@Test
func feedbackCopyHasNoPunitiveTerms() {
    let id = PracticeSourceMeasureID(partID: "P1", sourceMeasureIndex: 11, sourceNumberToken: "12A")
    let copy = PracticeIssueKind.allCasesForFeedbackTest.map { issue in
        PracticeFeedbackCuePresentation(event: PracticeFeedbackEvent(
            sequence: 1,
            sourceMeasureID: id,
            kind: .retryInvitation(issue: issue)
        )).title
    }
    let punitiveTerms = ["失败", "扣分", "错误太多", "差"]
    #expect(copy.allSatisfy { text in punitiveTerms.allSatisfy { text.localizedStandardContains($0) == false } })
    #expect(copy.allSatisfy { $0.localizedStandardContains("12A") })
}

private extension PracticeIssueKind {
    static let allCasesForFeedbackTest: [Self] = [.wrongNote, .missedNote, .incompleteChord]
}

@Test
func measurePitchStepStabilityUsesSourceAndHandCompositeIdentity() {
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "r")
    let id = PracticeSourceMeasureID(partID: "P1", sourceMeasureIndex: 0)
    let left = MeasurePracticeFacts(sourceMeasureID: id, handMode: .left, state: .pitchStepStable)
    let rightLearning = MeasurePracticeFacts(sourceMeasureID: id, handMode: .right, state: .learning)
    let rightStable = MeasurePracticeFacts(sourceMeasureID: id, handMode: .right, state: .pitchStepStable)
    let previous = SongPracticeProgress(identity: identity, measureFacts: [left, rightLearning], updatedAt: .now)
    let current = SongPracticeProgress(identity: identity, measureFacts: [left, rightStable], updatedAt: .now)
    let events = PracticeFeedbackPolicy().events(
        for: .attemptMatched(sourceMeasureID: id, handMode: .right),
        previousProgress: previous,
        progress: current,
        eventSequence: 1,
        passageSourceMeasureIDs: [id]
    )
    #expect(events.map(\.kind) == [.measurePitchStepsStable])
}

@Test
func passageCompletionUsesResolvedOccurrenceSourceIDs() {
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "r")
    let source0 = PracticeSourceMeasureID(partID: "P1", sourceMeasureIndex: 0)
    let source6 = PracticeSourceMeasureID(partID: "P1", sourceMeasureIndex: 6)
    let unrelated = PracticeSourceMeasureID(partID: "P1", sourceMeasureIndex: 3)
    let progress = SongPracticeProgress(
        identity: identity,
        measureFacts: [
            MeasurePracticeFacts(sourceMeasureID: source0, handMode: .both, state: .pitchStepStable),
            MeasurePracticeFacts(sourceMeasureID: source6, handMode: .both, state: .pitchStepStable),
            MeasurePracticeFacts(sourceMeasureID: unrelated, handMode: .both, state: .learning),
        ],
        updatedAt: .now
    )

    let events = PracticeFeedbackPolicy().events(
        for: .passageCompleted(handMode: .both),
        previousProgress: progress,
        progress: progress,
        eventSequence: 1,
        passageSourceMeasureIDs: [source6, source0]
    )

    #expect(events.map(\.kind) == [.passagePitchStepsStable])
}

@Test
func passageCompletionRequiresEveryExpectedMeasure() {
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "r")
    let first = PracticeSourceMeasureID(partID: "P1", sourceMeasureIndex: 0)
    let second = PracticeSourceMeasureID(partID: "P1", sourceMeasureIndex: 1)
    let progress = SongPracticeProgress(
        identity: identity,
        measureFacts: [MeasurePracticeFacts(sourceMeasureID: first, handMode: .both, state: .pitchStepStable)],
        updatedAt: .now
    )

    let events = PracticeFeedbackPolicy().events(
        for: .passageCompleted(handMode: .both),
        previousProgress: progress,
        progress: progress,
        eventSequence: 1,
        passageSourceMeasureIDs: [first, second]
    )
    #expect(events.map(\.kind) == [.roundSummaryReady])
}

@Test
func passageCompletionPresentsCoachingDecisionInsteadOfParallelStableCue() {
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "r")
    let source = PracticeSourceMeasureID(partID: "P1", sourceMeasureIndex: 0)
    let progress = SongPracticeProgress(
        identity: identity,
        measureFacts: [MeasurePracticeFacts(
            sourceMeasureID: source,
            handMode: .both,
            state: .pitchStepStable
        )],
        updatedAt: .now
    )

    let events = PracticeFeedbackPolicy().events(
        for: .passageCompleted(handMode: .both),
        previousProgress: progress,
        progress: progress,
        eventSequence: 1,
        passageSourceMeasureIDs: [source],
        coachingDecision: feedbackDecision(source: source)
    )

    #expect(events.map(\.kind) == [.roundSummaryReady])
}

@Test
func uncertainPitchCoachingRequestsEvidenceAndSuppressesFalseWrongNoteCue() throws {
    let source = PracticeSourceMeasureID(partID: "P1", sourceMeasureIndex: 0)
    let progress = SongPracticeProgress(
        identity: PracticeSongIdentity(songID: UUID(), scoreRevision: "r"),
        updatedAt: .now
    )
    let policy = CoachingPriorityPolicy()

    for candidate in [
        uncertainPitchDecision(source: source, confidence: 0.5, evidenceStatus: .observed),
        uncertainPitchDecision(source: source, confidence: 0.9, evidenceStatus: .insufficient),
    ] {
        let decision = try #require(policy.primaryDecision(from: [candidate]))
        #expect(decision.issue.kind == .evidence)
        #expect(decision.action.kind == .evidenceCheck)
        #expect(decision.action.completionCondition.target == .evidenceAvailable(dimension: .exactPitch))
        #expect(PracticeFeedbackPolicy().events(
            for: .attemptIssue(sourceMeasureID: source, issue: .wrongNote),
            previousProgress: progress,
            progress: progress,
            eventSequence: 1,
            passageSourceMeasureIDs: [source],
            coachingDecision: decision
        ).isEmpty)
    }
}

@Test
func evidenceCheckDoesNotHideUnrelatedRetryAndEmptyRangeIsNotActionable() {
    let source = PracticeSourceMeasureID(partID: "P1", sourceMeasureIndex: 0)
    let progress = SongPracticeProgress(
        identity: PracticeSongIdentity(songID: UUID(), scoreRevision: "r"),
        updatedAt: .now
    )
    let pedalDecision = CoachingDecision(
        issue: evidenceIssue(source: source, dimension: .pedalTiming, scoreRange: 0 ..< 480),
        action: CoachingAction(
            kind: .evidenceCheck,
            scoreRange: 0 ..< 480,
            repeatCount: 1,
            completionCondition: CoachingCompletionCondition(
                target: .evidenceAvailable(dimension: .pedalTiming)
            )
        )
    )
    let events = PracticeFeedbackPolicy().events(
        for: .attemptIssue(sourceMeasureID: source, issue: .wrongNote),
        previousProgress: progress,
        progress: progress,
        eventSequence: 1,
        passageSourceMeasureIDs: [source],
        coachingDecision: pedalDecision
    )
    #expect(events.map(\.kind) == [.retryInvitation(issue: .wrongNote)])

    let emptyRange = uncertainPitchDecision(
        source: source,
        confidence: 1,
        evidenceStatus: .observed,
        scoreRange: 0 ..< 0
    )
    #expect(CoachingPriorityPolicy().primaryDecision(from: [emptyRange]) == nil)
}

@Test
func repeatedIssueEventsHaveDistinctSequenceIdentity() {
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "r")
    let source = PracticeSourceMeasureID(partID: "P1", sourceMeasureIndex: 0)
    let progress = SongPracticeProgress(identity: identity, updatedAt: .now)
    let policy = PracticeFeedbackPolicy()
    let first = policy.events(
        for: .attemptIssue(sourceMeasureID: source, issue: .wrongNote),
        previousProgress: progress,
        progress: progress,
        eventSequence: 1,
        passageSourceMeasureIDs: [source]
    )
    let second = policy.events(
        for: .attemptIssue(sourceMeasureID: source, issue: .wrongNote),
        previousProgress: progress,
        progress: progress,
        eventSequence: 2,
        passageSourceMeasureIDs: [source]
    )
    #expect(first != second)
}

private func uncertainPitchDecision(
    source: PracticeSourceMeasureID,
    confidence: Double,
    evidenceStatus: PerformanceAssessmentEvidenceStatus,
    scoreRange: Range<Int> = 0 ..< 480
) -> CoachingDecision {
    let issue = MusicalIssue(
        kind: .pitch,
        scoreRange: scoreRange,
        measureOccurrenceIDs: [PracticeMeasureOccurrenceID(sourceMeasureID: source, occurrenceIndex: 0)],
        dimensionResults: [PerformanceAssessmentDimensionResult(
            dimension: .exactPitch,
            outcome: .incorrect,
            evidenceStatus: evidenceStatus,
            sampleCount: 1,
            confidence: confidence,
            evidence: []
        )],
        confidence: confidence,
        provenance: MusicalIssueProvenance(
            planID: ScorePerformancePlanID(rawValue: "feedback-test"),
            sourceGeneration: 1,
            rubricVersion: .capabilityAware
        )
    )
    return CoachingDecision(
        issue: issue,
        action: CoachingAction(
            kind: .pitchAccuracy,
            scoreRange: scoreRange,
            repeatCount: 1,
            completionCondition: CoachingCompletionCondition(
                target: .dimensionOutcome(dimension: .exactPitch, outcome: .correct)
            )
        )
    )
}

private func evidenceIssue(
    source: PracticeSourceMeasureID,
    dimension: PerformanceAssessmentDimension,
    scoreRange: Range<Int>
) -> MusicalIssue {
    MusicalIssue(
        kind: .evidence,
        scoreRange: scoreRange,
        measureOccurrenceIDs: [PracticeMeasureOccurrenceID(sourceMeasureID: source, occurrenceIndex: 0)],
        dimensionResults: [PerformanceAssessmentDimensionResult(
            dimension: dimension,
            outcome: .insufficientEvidence,
            evidenceStatus: .insufficient,
            sampleCount: 0,
            evidence: []
        )],
        confidence: nil,
        provenance: MusicalIssueProvenance(
            planID: ScorePerformancePlanID(rawValue: "feedback-test"),
            sourceGeneration: 1,
            rubricVersion: .capabilityAware
        )
    )
}
