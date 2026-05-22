@testable import LonelyPianistAVP
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
