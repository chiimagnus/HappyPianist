@testable import HappyPianistAVP
import Testing

@Test
func nextActionDoesNotInventAdviceWithoutEvidence() throws {
    let context = try feedbackContext(facts: [])
    #expect(PracticeNextActionPolicy().nextAction(for: context) == .continuePassage)
}

@Test
func nextActionLowersTempoWithoutInventingAProblemHand() throws {
    let facts = feedbackFacts(index: 2, failures: 2, issue: .missedNote)
    let context = try feedbackContext(facts: [facts])
    #expect(PracticeNextActionPolicy().nextAction(for: context) == .lowerTempo(0.7))
}

@Test
func nextActionExpandsStableFocusedPassage() throws {
    let facts = feedbackFacts(index: 2, state: .stable)
    let context = try feedbackContext(facts: [facts], isFullPassage: false)
    #expect(PracticeNextActionPolicy().nextAction(for: context) == .expandPassage)
}

private func feedbackContext(
    facts: [MeasurePracticeFacts],
    isFullPassage: Bool = false
) throws -> PracticeFeedbackContext {
    let source = PracticeSourceMeasureID(partID: "P1", sourceMeasureIndex: 0)
    let occurrence = PracticeMeasureOccurrenceID(sourceMeasureID: source, occurrenceIndex: 0)
    let passage = try #require(PracticePassage(start: occurrence, end: occurrence))
    return PracticeFeedbackContext(
        passageFacts: facts,
        passageSourceMeasureIDs: Set(facts.map(\.sourceMeasureID)).isEmpty ? [source] : Set(facts.map(\.sourceMeasureID)),
        configuration: PracticeRoundConfiguration(
            passage: passage,
            handMode: .both,
            tempoScale: 0.8,
            loopEnabled: true,
            requiredSuccesses: 3
        ),
        isFullPassage: isFullPassage
    )
}
