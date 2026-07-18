import Foundation
@testable import HappyPianistAVP

func testAttemptOutcome(
    matched: Bool,
    pressedNotes _: Set<Int> = [],
    expectedNotes _: [Int] = []
) -> StepAttemptMatchResult {
    matched ? .matched : .insufficientEvidence
}

func testSnapshotLine(_ fields: [(String, String?)]) -> String {
    PianoPerformanceSnapshotEncoder().encode(fields: fields)
}
