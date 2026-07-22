@testable import HappyPianistAVP
import Testing

@Test
func matcherRequiresAllExpectedNotesForChord() {
    let matcher = StepMatcher()
    #expect(matcher.matches(expectedNotes: [60, 64, 67], pressedNotes: [60, 64]) == false)
    #expect(matcher.matches(expectedNotes: [60, 64, 67], pressedNotes: [60, 64, 67]) == true)
}

@Test
func matcherRejectsAdjacentSemitones() {
    let matcher = StepMatcher()
    #expect(matcher.matches(expectedNotes: [60, 64], pressedNotes: [59, 65]) == false)
    #expect(matcher.matches(expectedNotes: [55, 57], pressedNotes: [55, 56]) == false)
}

@Test
func matcherAllowsExtraPressedNotesWhenExpectedSubsetMatches() {
    let matcher = StepMatcher()
    #expect(matcher.matches(expectedNotes: [60], pressedNotes: [60, 72]) == true)
}

@Test
func matcherSeparatesIncorrectFromInsufficientEvidence() {
    let matcher = StepMatcher()

    #expect(matcher.outcome(expectedNotes: [60, 64], pressedNotes: []) == .insufficientEvidence)
    #expect(matcher.outcome(expectedNotes: [60, 64], pressedNotes: [60]) == .insufficientEvidence)
    #expect(matcher.outcome(expectedNotes: [60, 64], pressedNotes: [59]) == .incorrect)
    #expect(matcher.outcome(expectedNotes: [60, 64], pressedNotes: [60, 64]) == .correct)
}
