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
    let fingerings = [MusicXMLFingering(
        text: "2",
        alternate: .enabled,
        placementToken: "above",
        hand: .left,
        provenance: .teacher
    )]
    let handFocus = ScoreHandAssignment(
        hand: .left,
        provenance: .score,
        confidence: 0.9
    )
    let completion = CoachingCompletionCondition(
        target: .dimensionOutcome(dimension: .onset, outcome: .correct)
    )
    let action = CoachingAction(
        kind: .onsetAlignment,
        scoreRange: issue.scoreRange,
        tempoRatio: 0.2,
        handFocus: handFocus,
        fingerings: fingerings,
        voiceFocus: CoachingVoiceFocus(partID: "P1", staff: 2, voice: 1),
        repeatCount: 0,
        referenceUse: .manualReplay,
        completionCondition: completion
    )
    let decision = CoachingDecision(issue: issue, action: action)

    #expect(action.tempoRatio == PracticeRoundConfiguration.supportedTempoRange.lowerBound)
    #expect(action.handFocus == handFocus)
    #expect(action.fingerings == fingerings)
    #expect(action.voiceFocus == CoachingVoiceFocus(partID: "P1", staff: 2, voice: 1))
    #expect(action.repeatCount == 1)
    #expect(action.referenceUse == .manualReplay)
    #expect(decision.issue == issue)
    #expect(decision.action == action)
}

@Test
func exercisePolicyUsesTheUniquelyProminentScoreVoice() throws {
    let plan = makeTestScorePerformancePlan(notes: [
        TestScorePerformanceNote(midiNote: 72, velocity: 112, onTick: 0, staff: 1, voice: 1),
        TestScorePerformanceNote(midiNote: 60, velocity: 72, onTick: 0, staff: 1, voice: 2),
    ])
    let issue = makeCoachingIssue(kind: .voicing, dimension: .voicing)

    let action = try #require(PracticeExercisePolicy().action(
        for: issue,
        scoreEvents: plan.noteEvents
    ))

    #expect(action.voiceFocus == CoachingVoiceFocus(partID: "P1", staff: 1, voice: 1))
    #expect(action.referenceUse == .score)
}

@Test
func decisionCarriesP13FingeringFactsWithoutCollapsingMultiplicityOrProvenance() async throws {
    let sourceNoteID = MusicXMLSourceNoteID(
        partID: "P1",
        sourceMeasureIndex: 0,
        sourceMeasureNumberToken: "1",
        staff: 1,
        voice: 1,
        sourceOrdinal: 0
    )
    let fingerings = [
        MusicXMLFingering(
            sourceID: MusicXMLFingeringSourceID(sourceNoteID: sourceNoteID, sourceOrdinal: 0),
            text: "2",
            substitution: .enabled,
            placementToken: "above",
            hand: .right,
            provenance: .score
        ),
        MusicXMLFingering(
            text: "3",
            alternate: .enabled,
            placementToken: "below",
            hand: .right,
            provenance: .teacher
        ),
        MusicXMLFingering(
            text: "4",
            hand: .right,
            provenance: .user
        ),
    ]
    let assignment = ScoreHandAssignment(hand: .right, provenance: .teacher, confidence: 0.9)
    let plan = makeTestScorePerformancePlan(notes: [TestScorePerformanceNote(
        midiNote: 60,
        onTick: 0,
        handAssignment: assignment,
        fingerings: fingerings
    )])
    let dimension = makeDimension(.exactPitch, outcome: .incorrect, confidence: 0.9)
    let assessment = PassagePerformanceAssessment(
        planID: plan.id,
        sourceGeneration: 7,
        tickRange: 0 ..< 480,
        rubricVersion: .capabilityAware,
        dimensions: [dimension],
        measures: []
    )

    let decision = try #require(await CoachingDecisionService().decision(
        for: assessment,
        scoreEvents: plan.noteEvents
    ))

    #expect(decision.action.handFocus == assignment)
    #expect(decision.action.fingerings == fingerings)
    #expect(decision.action.fingerings.map(\.sourceID) == fingerings.map(\.sourceID))
    #expect(decision.action.fingerings.map(\.provenance) == [.score, .teacher, .user])
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
func decisionServiceUsesMeasureEvidenceAndSkipsCorrectResults() async {
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

    let decisions = await CoachingDecisionService().candidates(for: assessment)

    #expect(decisions.map(\.issue.kind) == [.onset, .evidence])
    #expect(decisions.map(\.action.kind) == [.onsetAlignment, .evidenceCheck])
    #expect(decisions.allSatisfy { $0.issue.scoreRange == 0 ..< 480 })
    #expect(decisions.allSatisfy { $0.issue.measureOccurrenceIDs == [occurrenceID] })
    #expect(decisions.allSatisfy { $0.issue.provenance.sourceGeneration == 7 })
    #expect(decisions.contains { $0.issue.kind == .pitch } == false)
}

@Test
func decisionServiceRetainsOnlyUnlocalizedPassageEvidenceAlongsideMeasures() async {
    let measureOnset = makeDimension(.onset, outcome: .incorrect, confidence: 0.8)
    let passageExtra = makeDimension(.extraNotes, outcome: .incorrect, confidence: 0.9)
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
        dimensions: [measureOnset, passageExtra],
        measures: [MeasurePerformanceAssessment(
            occurrenceID: occurrenceID,
            tickRange: 0 ..< 480,
            dimensions: [measureOnset]
        )]
    )

    let decisions = await CoachingDecisionService().candidates(for: assessment)

    #expect(decisions.count == 2)
    #expect(decisions[0].issue.kind == .onset)
    #expect(decisions[0].issue.scoreRange == 0 ..< 480)
    #expect(decisions[0].issue.measureOccurrenceIDs == [occurrenceID])
    #expect(decisions[1].issue.kind == .pitch)
    #expect(decisions[1].issue.scoreRange == 0 ..< 960)
    #expect(decisions[1].issue.measureOccurrenceIDs.isEmpty)
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
            confidence: 0.7,
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

@Test
func decisionServiceCarriesSkipAndUnimprovedStateIntoPriorityPolicy() async throws {
    let assessment = makeCoachingAssessment(dimensions: [
        makeDimension(.onset, outcome: .incorrect, confidence: 0.9),
        makeDimension(.tempoContinuity, outcome: .incorrect, confidence: 0.8),
    ])
    let skipService = CoachingDecisionService()

    let skipped = try #require(await skipService.decision(for: assessment))
    #expect(skipped.action.kind == .onsetAlignment)
    await skipService.skip(skipped)
    #expect(try #require(await skipService.decision(for: assessment)).action.kind == .tempoStability)

    let retryService = CoachingDecisionService()
    let first = try #require(await retryService.decision(for: assessment))
    await retryService.accept(first)
    let repeated = try #require(await retryService.decision(for: assessment))
    #expect(repeated.action.kind == .onsetAlignment)
    await retryService.accept(repeated)
    let changed = try #require(await retryService.decision(for: assessment))
    #expect(changed.action.kind == .tempoStability)
}

@Test
func decisionServiceDoesNotRemeasureAcrossSourceGenerations() async throws {
    let reporter = InMemoryDiagnosticsReporter()
    let service = CoachingDecisionService(diagnosticsReporter: reporter)
    let firstAssessment = makeCoachingAssessment(
        sourceGeneration: 1,
        dimensions: [makeDimension(.onset, outcome: .incorrect, confidence: 0.9)]
    )
    let first = try #require(await service.decision(for: firstAssessment))
    let firstDecisionID = try #require(await reporter.events.first?.operationID)
    await service.accept(first)

    let next = try #require(await service.decision(for: makeCoachingAssessment(
        sourceGeneration: 2,
        dimensions: [makeDimension(.onset, outcome: .incorrect, confidence: 0.9)]
    )))
    let events = await reporter.events

    #expect(next.issue.provenance.sourceGeneration == 2)
    #expect(events.filter { $0.reason.contains("outcome=issued") }.count == 2)
    #expect(events.contains {
        $0.operationID == firstDecisionID && $0.reason.contains("outcome=remeasured")
    } == false)
}

@Test
func decisionServiceAggregatesMultipartRemeasurementConservatively() async throws {
    let reporter = InMemoryDiagnosticsReporter()
    let service = CoachingDecisionService(diagnosticsReporter: reporter)
    let initial = makeCoachingAssessment(dimensions: [
        makeDimension(.onset, outcome: .incorrect, confidence: 0.9),
    ])
    let decision = try #require(await service.decision(for: initial))
    let decisionID = try #require(await reporter.events.first?.operationID)
    await service.accept(decision)

    let correct = PerformanceAssessmentDimensionResult(
        dimension: .onset,
        outcome: .correct,
        evidenceStatus: .observed,
        measurement: PerformanceAssessmentMeasurement(value: 0.1, unit: .seconds),
        sampleCount: 2,
        confidence: 0.9,
        evidence: []
    )
    let incorrect = PerformanceAssessmentDimensionResult(
        dimension: .onset,
        outcome: .incorrect,
        evidenceStatus: .observed,
        measurement: PerformanceAssessmentMeasurement(value: 0.2, unit: .seconds),
        sampleCount: 3,
        confidence: 0.8,
        evidence: []
    )
    let remeasurement = PassagePerformanceAssessment(
        planID: initial.planID,
        sourceGeneration: initial.sourceGeneration,
        tickRange: initial.tickRange,
        rubricVersion: initial.rubricVersion,
        dimensions: [],
        measures: [
            makeMeasureAssessment(partID: "P1", dimensions: [correct]),
            makeMeasureAssessment(partID: "P2", dimensions: [incorrect]),
        ]
    )

    _ = await service.decision(for: remeasurement)
    let event = try #require(await reporter.events.first {
        $0.operationID == decisionID && $0.reason.contains("outcome=remeasured")
    })

    #expect(event.reason.contains("afterOutcome=incorrect"))
    #expect(event.reason.contains("afterSamples=5"))
    #expect(event.reason.contains("completion=unmet"))
}

@Test
func evidenceCheckCompletesOnlyWhenRemeasurementIsObserved() async throws {
    let initial = makeCoachingAssessment(dimensions: [makeDimension(
        .onset,
        outcome: .insufficientEvidence,
        confidence: nil,
        evidenceStatus: .insufficient
    )])

    let degradedReporter = InMemoryDiagnosticsReporter()
    let degradedService = CoachingDecisionService(diagnosticsReporter: degradedReporter)
    let degradedDecision = try #require(await degradedService.decision(for: initial))
    let degradedID = try #require(await degradedReporter.events.first?.operationID)
    await degradedService.accept(degradedDecision)
    _ = await degradedService.decision(for: makeCoachingAssessment(dimensions: [makeDimension(
        .onset,
        outcome: .incorrect,
        confidence: 0.5,
        evidenceStatus: .degraded
    )]))
    #expect(await degradedReporter.events.contains {
        $0.operationID == degradedID
            && $0.reason.contains("outcome=remeasured")
            && $0.reason.contains("completion=unmet")
    })

    let observedReporter = InMemoryDiagnosticsReporter()
    let observedService = CoachingDecisionService(diagnosticsReporter: observedReporter)
    let observedDecision = try #require(await observedService.decision(for: initial))
    let observedID = try #require(await observedReporter.events.first?.operationID)
    await observedService.accept(observedDecision)
    _ = await observedService.decision(for: makeCoachingAssessment(dimensions: [makeDimension(
        .onset,
        outcome: .incorrect,
        confidence: 0.9
    )]))
    #expect(await observedReporter.events.contains {
        $0.operationID == observedID
            && $0.reason.contains("outcome=remeasured")
            && $0.reason.contains("completion=met")
    })
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

private func makeCoachingAssessment(
    sourceGeneration: UInt64 = 1,
    dimensions: [PerformanceAssessmentDimensionResult]
) -> PassagePerformanceAssessment {
    PassagePerformanceAssessment(
        planID: ScorePerformancePlanID(rawValue: "plan"),
        sourceGeneration: sourceGeneration,
        tickRange: 0 ..< 480,
        rubricVersion: .capabilityAware,
        dimensions: dimensions,
        measures: []
    )
}

private func makeMeasureAssessment(
    partID: String,
    dimensions: [PerformanceAssessmentDimensionResult]
) -> MeasurePerformanceAssessment {
    MeasurePerformanceAssessment(
        occurrenceID: PracticeMeasureOccurrenceID(
            sourceMeasureID: PracticeSourceMeasureID(
                partID: partID,
                sourceMeasureIndex: 0,
                sourceNumberToken: "1"
            ),
            occurrenceIndex: 0
        ),
        tickRange: 0 ..< 480,
        dimensions: dimensions
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
