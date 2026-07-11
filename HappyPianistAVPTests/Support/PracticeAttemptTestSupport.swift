import Foundation
@testable import HappyPianistAVP

func testAttemptOutcome(
    matched: Bool,
    pressedNotes: Set<Int> = [],
    expectedNotes: [Int] = []
) -> StepAttemptMatchResult {
    let evidence = PracticeAttemptEvidence(
        expectedNotes: Set(expectedNotes),
        observedNotes: pressedNotes,
        handMode: .both,
        source: .handContact,
        isPartialEvidence: false,
        debugMessage: "test"
    )
    return matched ? .matched(evidence: evidence) : .insufficientEvidence(evidence: evidence)
}
