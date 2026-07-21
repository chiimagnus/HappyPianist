protocol StepMatcherProtocol {
    func matches(expectedNotes: [Int], pressedNotes: Set<Int>) -> Bool
}

struct StepMatcher: StepMatcherProtocol {
    func matches(expectedNotes: [Int], pressedNotes: Set<Int>) -> Bool {
        outcome(expectedNotes: expectedNotes, pressedNotes: pressedNotes) == .correct
    }

    func outcome(expectedNotes: [Int], pressedNotes: Set<Int>) -> PracticeEvidenceOutcome {
        let expected = Set(expectedNotes)
        guard expected.isEmpty == false, pressedNotes.isEmpty == false else {
            return .insufficientEvidence
        }
        if expected.isSubset(of: pressedNotes) {
            return .correct
        }
        return pressedNotes.isSubset(of: expected) ? .insufficientEvidence : .incorrect
    }
}
