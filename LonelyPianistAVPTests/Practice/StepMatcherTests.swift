@testable import LonelyPianistAVP
import Testing

@Test
func matcherRequiresAllExpectedNotesForChord() {
    let matcher = StepMatcher()
    #expect(matcher.matches(expectedNotes: [60, 64, 67], pressedNotes: [60, 64], tolerance: 0) == false)
    #expect(matcher.matches(expectedNotes: [60, 64, 67], pressedNotes: [60, 64, 67], tolerance: 0) == true)
}

@Test
func matcherAllowsTolerancePlusMinusOne() {
    let matcher = StepMatcher()
    #expect(matcher.matches(expectedNotes: [60, 64], pressedNotes: [59, 65], tolerance: 1) == true)
    #expect(matcher.matches(expectedNotes: [60, 64], pressedNotes: [58, 66], tolerance: 1) == false)
    #expect(matcher.matches(expectedNotes: [55, 57], pressedNotes: [55, 56], tolerance: 1) == true)
}

@Test
func matcherAllowsExtraPressedNotesWhenExpectedSubsetMatches() {
    let matcher = StepMatcher()
    #expect(matcher.matches(expectedNotes: [60], pressedNotes: [60, 72], tolerance: 0) == true)
}
