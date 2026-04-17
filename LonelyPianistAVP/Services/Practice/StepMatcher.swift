import Foundation

protocol StepMatcherProtocol {
    func matches(expectedNotes: [Int], pressedNotes: Set<Int>, tolerance: Int) -> Bool
}

struct StepMatcher: StepMatcherProtocol {
    func matches(expectedNotes: [Int], pressedNotes: Set<Int>, tolerance: Int) -> Bool {
        guard expectedNotes.isEmpty == false else { return false }
        guard pressedNotes.isEmpty == false else { return false }

        let sortedExpected = expectedNotes.sorted()
        var remainingPressed = pressedNotes

        for expected in sortedExpected {
            guard let matched = remainingPressed.first(where: { abs($0 - expected) <= tolerance }) else {
                return false
            }
            remainingPressed.remove(matched)
        }
        return true
    }
}
