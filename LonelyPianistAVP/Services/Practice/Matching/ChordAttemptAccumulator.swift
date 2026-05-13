import Foundation

protocol ChordAttemptAccumulatorProtocol {
    func register(
        pressedNotes: Set<Int>,
        expectedNotes: [Int],
        tolerance: Int,
        at timestamp: Date
    ) -> Bool
    func reset()
}

final class ChordAttemptAccumulator: ChordAttemptAccumulatorProtocol {
    private let windowSeconds: TimeInterval
    private let matcher: StepMatcherProtocol

    private var windowStart: Date?
    private var accumulatedPressedNotes: Set<Int> = []

    init(windowSeconds: TimeInterval = 0.6, matcher: StepMatcherProtocol = StepMatcher()) {
        self.windowSeconds = windowSeconds
        self.matcher = matcher
    }

    func register(
        pressedNotes: Set<Int>,
        expectedNotes: [Int],
        tolerance: Int,
        at timestamp: Date
    ) -> Bool {
        guard pressedNotes.isEmpty == false else { return false }
        guard expectedNotes.isEmpty == false else { return false }

        if let windowStart, timestamp.timeIntervalSince(windowStart) > windowSeconds {
            reset()
        }

        if windowStart == nil {
            windowStart = timestamp
        }
        accumulatedPressedNotes.formUnion(pressedNotes)

        let matched = matcher.matches(
            expectedNotes: expectedNotes,
            pressedNotes: accumulatedPressedNotes,
            tolerance: tolerance
        )
        if matched {
            reset()
            return true
        }
        return false
    }

    func reset() {
        windowStart = nil
        accumulatedPressedNotes.removeAll()
    }
}
