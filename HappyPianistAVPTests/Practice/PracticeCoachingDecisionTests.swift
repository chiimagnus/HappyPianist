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

    let decisions = CoachingDecisionService().candidates(for: assessment)

    #expect(decisions.map(\.issue.kind) == [.onset, .evidence])
    #expect(decisions.map(\.action.kind) == [.onsetAlignment, .evidenceCheck])
    #expect(decisions.allSatisfy { $0.issue.scoreRange == 0 ..< 480 })
    #expect(decisions.allSatisfy { $0.issue.measureOccurrenceIDs == [occurrenceID] })
    #expect(decisions.allSatisfy { $0.issue.provenance.sourceGeneration == 7 })
    #expect(decisions.contains { $0.issue.kind == .pitch } == false)
}

@Test
func priorityPolicyRanksPrerequisitesSeverityConfidenceAndCoverage() {
    guard
        let evidence = makeDecision(
            kind: .evidence,
            dimension: .pedalTiming,
            confidence: nil,
            evidenceStatus: .insufficient,
            scoreRange: 960 ..< 1_440
        ),
        let pitch = makeDecision(
            kind: .pitch,
            dimension: .exactPitch,
            confidence: 0.5,
            scoreRange: 0 ..< 480
        ),
        let phrase = makeDecision(
            kind: .phrase,
            dimension: .phraseContinuity,
            confidence: 1,
            scoreRange: 480 ..< 960
        ),
        let lowerConfidenceOnset = makeDecision(
            kind: .onset,
            dimension: .onset,
            confidence: 0.6,
            scoreRange: 480 ..< 960
        ),
        let higherConfidenceOnset = makeDecision(
            kind: .onset,
            dimension: .onset,
            confidence: 0.9,
            scoreRange: 960 ..< 1_440
        ),
        let degradedOnset = makeDecision(
            kind: .onset,
            dimension: .onset,
            confidence: 0.9,
            evidenceStatus: .degraded,
            scoreRange: 1_440 ..< 1_920
        )
    else {
        Issue.record("Expected actionable coaching decisions")
        return
    }
    let policy = CoachingPriorityPolicy()

    #expect(policy.primaryDecision(from: [pitch, evidence, phrase]) == evidence)
    #expect(policy.primaryDecision(from: [phrase, pitch]) == pitch)
    #expect(policy.primaryDecision(from: [lowerConfidenceOnset, higherConfidenceOnset]) == higherConfidenceOnset)
    #expect(policy.primaryDecision(from: [degradedOnset, higherConfidenceOnset]) == higherConfidenceOnset)
}

@Test
func priorityPolicyHonorsSkipAndStopsRepeatingUnimprovedAction() {
    guard
        let onset = makeDecision(
            kind: .onset,
            dimension: .onset,
            confidence: 0.9,
            scoreRange: 0 ..< 480
        ),
        let tempo = makeDecision(
            kind: .tempo,
            dimension: .tempoContinuity,
            confidence: 0.8,
            scoreRange: 480 ..< 960
        )
    else {
        Issue.record("Expected actionable coaching decisions")
        return
    }
    let policy = CoachingPriorityPolicy()

    let skipped = policy.primaryDecision(
        from: [onset, tempo],
        context: CoachingPriorityContext(skippedDecisions: [CoachingDecisionSignature(onset)])
    )
    #expect(skipped == tempo)

    let continued = policy.primaryDecision(
        from: [onset, tempo],
        context: CoachingPriorityContext(
            previousDecision: tempo,
            consecutiveUnimprovedAssessments: 1
        )
    )
    #expect(continued == tempo)

    let changed = policy.primaryDecision(
        from: [onset, tempo],
        context: CoachingPriorityContext(
            previousDecision: onset,
            consecutiveUnimprovedAssessments: 2
        )
    )
    #expect(changed == tempo)
}

private func makeCoachingIssue(
    kind: MusicalIssueKind = .onset,
    dimension: PerformanceAssessmentDimension = .onset,
    outcome: PracticeEvidenceOutcome = .incorrect,
    confidence: Double? = 0.8,
    evidenceStatus: PerformanceAssessmentEvidenceStatus = .observed,
    scoreRange: Range<Int> = 0 ..< 480
) -> MusicalIssue {
    let result = makeDimension(
        dimension,
        outcome: outcome,
        confidence: confidence,
        evidenceStatus: evidenceStatus
    )
    return MusicalIssue(
        kind: kind,
        scoreRange: scoreRange,
        dimensionResults: [result],
        confidence: confidence,
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
    confidence: Double?,
    evidenceStatus: PerformanceAssessmentEvidenceStatus = .observed
) -> PerformanceAssessmentDimensionResult {
    PerformanceAssessmentDimensionResult(
        dimension: dimension,
        outcome: outcome,
        evidenceStatus: evidenceStatus,
        sampleCount: 2,
        confidence: confidence,
        evidence: []
    )
}

private func makeDecision(
    kind: MusicalIssueKind,
    dimension: PerformanceAssessmentDimension,
    confidence: Double?,
    evidenceStatus: PerformanceAssessmentEvidenceStatus = .observed,
    scoreRange: Range<Int>
) -> CoachingDecision? {
    let outcome: PracticeEvidenceOutcome = kind == .evidence ? .insufficientEvidence : .incorrect
    let issue = makeCoachingIssue(
        kind: kind,
        dimension: dimension,
        outcome: outcome,
        confidence: confidence,
        evidenceStatus: evidenceStatus,
        scoreRange: scoreRange
    )
    return PracticeExercisePolicy().action(for: issue).map {
        CoachingDecision(issue: issue, action: $0)
    }
}
