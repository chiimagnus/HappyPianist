@testable import HappyPianistAVP
import Testing

@Test
func handAssignmentPreservesProvenanceAndClampsConfidence() {
    let assignment = ScoreHandAssignment(hand: .left, provenance: .teacher, confidence: 1.4)
    #expect(assignment.hand == .left)
    #expect(assignment.provenance == .teacher)
    #expect(assignment.confidence == 1)
    #expect(ScoreHandAssignment(hand: .right, provenance: .heuristic, confidence: .nan).confidence == nil)
    #expect(ScoreHandAssignment.unknown.hand == .unknown)
}

@Test
func staffDoesNotImplicitlyAssignAHand() {
    let upperStaff = PracticeStepNote(midiNote: 60, staff: 1, handAssignment: .unknown)
    let lowerStaff = PracticeStepNote(midiNote: 48, staff: 2, handAssignment: .unknown)
    let thirdStaff = PracticeStepNote(midiNote: 36, staff: 3, handAssignment: .unknown)

    #expect(upperStaff.hand == .unknown)
    #expect(lowerStaff.hand == .unknown)
    #expect(thirdStaff.hand == .unknown)
}

@Test
func explicitAssignmentCanCrossStaff() {
    let leftOnUpperStaff = PracticeStepNote(
        midiNote: 67,
        staff: 1,
        handAssignment: ScoreHandAssignment(hand: .left, provenance: .teacher)
    )
    let rightOnLowerStaff = PracticeStepNote(
        midiNote: 52,
        staff: 2,
        handAssignment: ScoreHandAssignment(hand: .right, provenance: .score)
    )

    #expect(leftOnUpperStaff.hand == .left)
    #expect(rightOnLowerStaff.hand == .right)
}

@Test
func highlightNoteRequiresExplicitAssignment() {
    let note = PianoHighlightNote(
        occurrenceID: "n1",
        midiNote: 60,
        staff: 1,
        voice: 1,
        velocity: 96,
        onTick: 0,
        offTick: 1,
        fingerings: [],
        handAssignment: .unknown
    )

    #expect(note.hand == .unknown)
}

@Test
func coachingPreservesHeuristicConfidenceButDoesNotInferUnknownStaffHand() throws {
    let issue = MusicalIssue(
        kind: .pitch,
        scoreRange: 0 ..< 480,
        dimensionResults: [PerformanceAssessmentDimensionResult(
            dimension: .exactPitch,
            outcome: .incorrect,
            evidenceStatus: .observed,
            sampleCount: 1,
            confidence: 0.8,
            evidence: []
        )],
        confidence: 0.8,
        provenance: MusicalIssueProvenance(
            planID: ScorePerformancePlanID(rawValue: "plan"),
            sourceGeneration: 1,
            rubricVersion: .capabilityAware
        )
    )
    let heuristic = ScoreHandAssignment(hand: .right, provenance: .heuristic, confidence: 0.72)
    let heuristicPlan = makeTestScorePerformancePlan(notes: [TestScorePerformanceNote(
        midiNote: 72,
        onTick: 0,
        staff: 1,
        handAssignment: heuristic
    )])
    let unknownPlan = makeTestScorePerformancePlan(notes: [TestScorePerformanceNote(
        midiNote: 36,
        onTick: 0,
        staff: 2,
        handAssignment: .unknown
    )])
    let policy = PracticeExercisePolicy()

    #expect(policy.action(for: issue, scoreEvents: heuristicPlan.noteEvents)?.handFocus == heuristic)
    #expect(policy.action(for: issue, scoreEvents: unknownPlan.noteEvents)?.handFocus == nil)
}
