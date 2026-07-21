import Foundation
@testable import HappyPianistAVP
import Testing

@Test
func hotspotUsesCoachingDecisionOccurrence() throws {
    let source = PracticeSourceMeasureID(partID: "P1", sourceMeasureIndex: 2)
    let decision = feedbackDecision(source: source, occurrenceIndex: 3)

    let hotspot = try #require(PracticeHotspotPolicy().hotspot(for: decision))

    #expect(hotspot.sourceMeasureID == source)
    #expect(decision.issue.measureOccurrenceIDs == [PracticeMeasureOccurrenceID(
        sourceMeasureID: source,
        occurrenceIndex: 3
    )])
}

@Test
func hotspotNeedsTraceableCoachingDecision() {
    #expect(PracticeHotspotPolicy().hotspot(for: nil) == nil)
    #expect(PracticeHotspotPolicy().hotspot(for: feedbackDecision(
        source: PracticeSourceMeasureID(partID: "P1", sourceMeasureIndex: 1),
        includeOccurrence: false
    )) == nil)
}

func feedbackFacts(
    index: Int,
    handMode: PracticeHandMode = .both,
    state: MeasurePitchStepLearningState = .learning,
    failures: Int = 0,
    issue: PracticeIssueKind? = nil,
    date: Date? = nil
) -> MeasurePracticeFacts {
    MeasurePracticeFacts(
        sourceMeasureID: PracticeSourceMeasureID(partID: "P1", sourceMeasureIndex: index),
        handMode: handMode,
        state: state,
        failedAttempts: failures,
        recentIssue: issue,
        lastAttemptAt: date
    )
}

func feedbackDecision(
    source: PracticeSourceMeasureID,
    occurrenceIndex: Int = 0,
    tempoRatio: Double? = nil,
    includeOccurrence: Bool = true
) -> CoachingDecision {
    let dimension = PerformanceAssessmentDimensionResult(
        dimension: .exactPitch,
        outcome: .incorrect,
        evidenceStatus: .observed,
        sampleCount: 1,
        confidence: 1,
        evidence: []
    )
    let issue = MusicalIssue(
        kind: .pitch,
        scoreRange: 0 ..< 480,
        measureOccurrenceIDs: includeOccurrence
            ? [PracticeMeasureOccurrenceID(
                sourceMeasureID: source,
                occurrenceIndex: occurrenceIndex
            )]
            : [],
        dimensionResults: [dimension],
        confidence: 1,
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
            scoreRange: issue.scoreRange,
            tempoRatio: tempoRatio,
            repeatCount: 3,
            referenceUse: .manualReplay,
            completionCondition: CoachingCompletionCondition(
                target: .dimensionOutcome(dimension: .exactPitch, outcome: .correct)
            )
        )
    )
}
