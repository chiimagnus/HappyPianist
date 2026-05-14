import Foundation

protocol ChordAttemptAccumulatorProtocol {
    func register(
        pressedNotes: Set<Int>,
        expectedNotes: [Int],
        tolerance: Int,
        at timestamp: Date
    ) -> Bool

    func registerHandSeparated(
        pressedNotes: Set<Int>,
        expectedRightNotes: [Int],
        expectedLeftNotes: [Int],
        tolerance: Int,
        at timestamp: Date
    ) -> Bool
    func reset()
}

extension ChordAttemptAccumulatorProtocol {
    func registerHandSeparated(
        pressedNotes: Set<Int>,
        expectedRightNotes: [Int],
        expectedLeftNotes: [Int],
        tolerance: Int,
        at timestamp: Date
    ) -> Bool {
        let expectedUnion = Set(expectedRightNotes + expectedLeftNotes).sorted()
        return register(
            pressedNotes: pressedNotes,
            expectedNotes: expectedUnion,
            tolerance: tolerance,
            at: timestamp
        )
    }
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

    func registerHandSeparated(
        pressedNotes: Set<Int>,
        expectedRightNotes: [Int],
        expectedLeftNotes: [Int],
        tolerance: Int,
        at timestamp: Date
    ) -> Bool {
        guard pressedNotes.isEmpty == false else { return false }

        let expectedUnion = Set(expectedRightNotes + expectedLeftNotes)
        guard expectedUnion.isEmpty == false else { return false }

        if let windowStart, timestamp.timeIntervalSince(windowStart) > windowSeconds {
            reset()
        }

        if windowStart == nil {
            windowStart = timestamp
        }
        accumulatedPressedNotes.formUnion(pressedNotes)

        let rightMatched = expectedRightNotes.isEmpty
            ? true
            : matcher.matches(
                expectedNotes: expectedRightNotes,
                pressedNotes: accumulatedPressedNotes,
                tolerance: tolerance
            )
        let leftMatched = expectedLeftNotes.isEmpty
            ? true
            : matcher.matches(
                expectedNotes: expectedLeftNotes,
                pressedNotes: accumulatedPressedNotes,
                tolerance: tolerance
            )

        if rightMatched, leftMatched {
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
