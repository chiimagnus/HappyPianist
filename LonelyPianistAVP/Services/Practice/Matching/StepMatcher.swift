import Foundation

protocol StepMatcherProtocol {
    func matches(expectedNotes: [Int], pressedNotes: Set<Int>, tolerance: Int) -> Bool
}

struct StepMatcher: StepMatcherProtocol {
    func matches(expectedNotes: [Int], pressedNotes: Set<Int>, tolerance: Int) -> Bool {
        guard expectedNotes.isEmpty == false else { return false }
        guard pressedNotes.isEmpty == false else { return false }

        let sortedExpected = expectedNotes.sorted()
        let sortedPressed = pressedNotes.sorted()
        var usedPressed = Array(repeating: false, count: sortedPressed.count)

        func dfs(expectedIndex: Int) -> Bool {
            if expectedIndex == sortedExpected.count {
                return true
            }

            let expected = sortedExpected[expectedIndex]
            for pressedIndex in sortedPressed.indices where usedPressed[pressedIndex] == false {
                let pressed = sortedPressed[pressedIndex]
                guard abs(pressed - expected) <= tolerance else { continue }
                usedPressed[pressedIndex] = true
                if dfs(expectedIndex: expectedIndex + 1) {
                    return true
                }
                usedPressed[pressedIndex] = false
            }
            return false
        }

        return dfs(expectedIndex: 0)
    }
}
