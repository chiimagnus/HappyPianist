@testable import HappyPianistAVP
import Testing

@Test
func fromStaffTreatsNilAsRightHand() {
    #expect(ScoreHand.fromStaff(nil) == .right)
}

@Test
func fromStaffTreatsStaffOneAsRightHand() {
    #expect(ScoreHand.fromStaff(1) == .right)
}

@Test
func fromStaffTreatsStaffTwoOrGreaterAsLeftHand() {
    #expect(ScoreHand.fromStaff(2) == .left)
    #expect(ScoreHand.fromStaff(3) == .left)
}

@Test
func handAssignmentPreservesProvenanceAndClampsConfidence() {
    let assignment = ScoreHandAssignment(hand: .left, provenance: .teacher, confidence: 1.4)
    #expect(assignment.hand == .left)
    #expect(assignment.provenance == .teacher)
    #expect(assignment.confidence == 1)
    #expect(ScoreHandAssignment.unknown.hand == .unknown)
}

@Test
func notesWithoutAssignmentRemainUnknownInsteadOfDefaultingRight() {
    #expect(PracticeStepNote(midiNote: 60, staff: 1).hand == .unknown)
    #expect(PianoHighlightNote(
        occurrenceID: "n1",
        midiNote: 60,
        staff: 1,
        voice: 1,
        velocity: 96,
        onTick: 0,
        offTick: 1,
        fingeringText: nil
    ).hand == .unknown)
}
