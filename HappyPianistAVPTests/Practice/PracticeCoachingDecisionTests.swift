@testable import HappyPianistAVP
import Testing

@Test
func performanceDimensionsMapToMusicalIssueTaxonomy() {
    let expected: [PerformanceAssessmentDimension: MusicalIssueKind] = [
        .exactPitch: .pitch,
        .extraNotes: .pitch,
        .missingNotes: .pitch,
        .onset: .onset,
        .tempoRelativeTiming: .tempo,
        .chordSpread: .chordSpread,
        .duration: .duration,
        .release: .duration,
        .articulation: .articulation,
        .velocity: .dynamicContour,
        .dynamicContour: .dynamicContour,
        .voicing: .voicing,
        .pedalTiming: .pedal,
        .pedalValue: .pedal,
        .tempoContinuity: .tempo,
        .phraseContinuity: .phrase,
    ]

    #expect(expected.count == PerformanceAssessmentDimension.allCases.count)
    for dimension in PerformanceAssessmentDimension.allCases {
        #expect(dimension.musicalIssueKind == expected[dimension])
    }
}

@Test
func musicalIssueRetainsAssessmentEvidenceAndBoundsConfidence() {
    let dimension = PerformanceAssessmentDimensionResult(
        dimension: .onset,
        outcome: .incorrect,
        evidenceStatus: .observed,
        measurement: PerformanceAssessmentMeasurement(value: 0.12, unit: .seconds),
        sampleCount: 3,
        confidence: 0.8,
        evidence: []
    )
    let provenance = MusicalIssueProvenance(
        planID: ScorePerformancePlanID(rawValue: "plan"),
        sourceGeneration: 4,
        rubricVersion: .capabilityAware
    )

    let issue = MusicalIssue(
        kind: .onset,
        scoreRange: 480 ..< 960,
        dimensionResults: [dimension],
        confidence: 1.2,
        provenance: provenance
    )

    #expect(issue.scoreRange == 480 ..< 960)
    #expect(issue.dimensionResults == [dimension])
    #expect(issue.confidence == 1)
    #expect(issue.provenance == provenance)

    let unknownConfidence = MusicalIssue(
        kind: .evidence,
        scoreRange: 480 ..< 960,
        dimensionResults: [dimension],
        confidence: .infinity,
        provenance: provenance
    )
    #expect(unknownConfidence.confidence == nil)
}

@Test
func coachingActionCarriesExecutableParametersAndNormalizesBounds() {
    let issue = makeCoachingIssue()
    let handFocus = ScoreHandAssignment(
        hand: .left,
        provenance: .score,
        confidence: 0.9
    )
    let completion = CoachingCompletionCondition(
        target: .dimensionOutcome(dimension: .onset, outcome: .correct),
        consecutiveAssessments: 0
    )
    let action = CoachingAction(
        kind: .onsetAlignment,
        scoreRange: issue.scoreRange,
        tempoRatio: 0.2,
        handFocus: handFocus,
        voiceFocus: CoachingVoiceFocus(partID: "P1", staff: 2, voice: 1),
        repeatCount: 0,
        referenceUse: .manualReplay,
        cueUse: .metronome,
        completionCondition: completion
    )
    let decision = CoachingDecision(issue: issue, action: action)

    #expect(action.tempoRatio == PracticeRoundConfiguration.supportedTempoRange.lowerBound)
    #expect(action.handFocus == handFocus)
    #expect(action.voiceFocus == CoachingVoiceFocus(partID: "P1", staff: 2, voice: 1))
    #expect(action.repeatCount == 1)
    #expect(action.referenceUse == .manualReplay)
    #expect(action.cueUse == .metronome)
    #expect(action.completionCondition.consecutiveAssessments == 1)
    #expect(decision.issue == issue)
    #expect(decision.action == action)
}

@Test
func exercisePolicyMapsEveryIssueToASpecificRemeasurableAction() {
    let expected: [(MusicalIssueKind, PerformanceAssessmentDimension, CoachingActionKind)] = [
        (.pitch, .exactPitch, .pitchAccuracy),
        (.onset, .onset, .onsetAlignment),
        (.chordSpread, .chordSpread, .chordSynchronization),
        (.duration, .duration, .durationControl),
        (.articulation, .articulation, .articulationControl),
        (.voicing, .voicing, .voiceBalance),
        (.dynamicContour, .dynamicContour, .dynamicShaping),
        (.pedal, .pedalTiming, .pedalCoordination),
        (.tempo, .tempoContinuity, .tempoStability),
        (.phrase, .phraseContinuity, .phraseContinuity),
        (.evidence, .onset, .evidenceCheck),
    ]
    let policy = PracticeExercisePolicy()

    #expect(expected.count == MusicalIssueKind.allCases.count)
    for (issueKind, dimension, actionKind) in expected {
        let outcome: PracticeEvidenceOutcome = issueKind == .evidence
            ? .insufficientEvidence
            : .incorrect
        let issue = makeCoachingIssue(kind: issueKind, dimension: dimension, outcome: outcome)
        let action = policy.action(for: issue)

        #expect(action?.kind == actionKind)
        #expect(action?.scoreRange == issue.scoreRange)
        if issueKind == .evidence {
            #expect(action?.completionCondition.target == .evidenceAvailable(dimension: dimension))
        } else {
            #expect(action?.completionCondition.target == .dimensionOutcome(
                dimension: dimension,
                outcome: .correct
            ))
        }
    }
}

@Test
func decisionServiceUsesMeasureEvidenceAndSkipsCorrectResults() {
    let correctPitch = makeDimension(.exactPitch, outcome: .correct, confidence: 1)
    let incorrectOnset = makeDimension(.onset, outcome: .incorrect, confidence: 0.8)
    let insufficientPedal = makeDimension(
        .pedalTiming,
        outcome: .insufficientEvidence,
        confidence: nil
    )
    let occurrenceID = PracticeMeasureOccurrenceID(
        sourceMeasureID: PracticeSourceMeasureID(
            partID: "P1",
            sourceMeasureIndex: 0,
            sourceNumberToken: "1"
        ),
        occurrenceIndex: 0
    )
    let assessment = PassagePerformanceAssessment(
        planID: ScorePerformancePlanID(rawValue: "plan"),
        sourceGeneration: 7,
        tickRange: 0 ..< 960,
        rubricVersion: .capabilityAware,
        dimensions: [incorrectOnset],
        measures: [MeasurePerformanceAssessment(
            occurrenceID: occurrenceID,
            tickRange: 0 ..< 480,
            dimensions: [correctPitch, incorrectOnset, insufficientPedal]
        )]
    )

    let decisions = CoachingDecisionService().decisions(for: assessment)

    #expect(decisions.map(\.issue.kind) == [.onset, .evidence])
    #expect(decisions.map(\.action.kind) == [.onsetAlignment, .evidenceCheck])
    #expect(decisions.allSatisfy { $0.issue.scoreRange == 0 ..< 480 })
    #expect(decisions.allSatisfy { $0.issue.provenance.sourceGeneration == 7 })
    #expect(decisions.contains { $0.issue.kind == .pitch } == false)
}

private func makeCoachingIssue(
    kind: MusicalIssueKind = .onset,
    dimension: PerformanceAssessmentDimension = .onset,
    outcome: PracticeEvidenceOutcome = .incorrect
) -> MusicalIssue {
    let result = makeDimension(
        dimension,
        outcome: outcome,
        confidence: 0.8
    )
    return MusicalIssue(
        kind: kind,
        scoreRange: 0 ..< 480,
        dimensionResults: [result],
        confidence: 0.8,
        provenance: MusicalIssueProvenance(
            planID: ScorePerformancePlanID(rawValue: "plan"),
            sourceGeneration: 1,
            rubricVersion: .capabilityAware
        )
    )
}

private func makeDimension(
    _ dimension: PerformanceAssessmentDimension,
    outcome: PracticeEvidenceOutcome,
    confidence: Double?
) -> PerformanceAssessmentDimensionResult {
    PerformanceAssessmentDimensionResult(
        dimension: dimension,
        outcome: outcome,
        evidenceStatus: .observed,
        sampleCount: 2,
        confidence: confidence,
        evidence: []
    )
}
