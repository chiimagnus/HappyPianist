@testable import HappyPianistAVP
import Testing

@Test
func nextActionDoesNotInventAdviceWithoutEvidence() throws {
    let context = try feedbackContext(facts: [])
    #expect(PracticeNextActionPolicy().nextAction(for: context) == .continuePassage)
}

@Test
func nextActionUsesCoachingTempoWithoutReadingFailureCounts() throws {
    let source = PracticeSourceMeasureID(partID: "P1", sourceMeasureIndex: 2)
    let facts = feedbackFacts(index: 2, failures: 99, issue: .missedNote)
    let context = try feedbackContext(
        facts: [facts],
        coachingDecision: feedbackDecision(source: source, tempoRatio: 0.7)
    )
    guard case let .lowerTempo(scale) = PracticeNextActionPolicy().nextAction(for: context) else {
        Issue.record("Expected lower-tempo advice")
        return
    }
    #expect(abs(scale - 0.7) < 0.0001)
}

@Test
func nextActionUsesExplicitBasicRetryWithoutAssessment() throws {
    let facts = feedbackFacts(index: 2, failures: 1, issue: .missedNote)
    let context = try feedbackContext(facts: [facts])

    #expect(PracticeNextActionPolicy().nextAction(for: context) == .retryMeasure(facts.sourceMeasureID))
}

@Test
func nextActionExpandsStableFocusedPassage() throws {
    let facts = feedbackFacts(index: 2, state: .pitchStepStable)
    let context = try feedbackContext(facts: [facts], isFullPassage: false)
    #expect(PracticeNextActionPolicy().nextAction(for: context) == .expandPassage)
}

private func feedbackContext(
    facts: [MeasurePracticeFacts],
    isFullPassage: Bool = false,
    coachingDecision: CoachingDecision? = nil
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
        isFullPassage: isFullPassage,
        coachingDecision: coachingDecision
    )
}
