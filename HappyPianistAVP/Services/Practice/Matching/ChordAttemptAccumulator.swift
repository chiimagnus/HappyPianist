import Foundation

enum ChordOnsetExpectation: Equatable {
    case simultaneous
    case rolled
}

struct HandSeparatedNoteEvidence: Equatable {
    let right: Set<Int>
    let left: Set<Int>

    var all: Set<Int> { right.union(left) }
    var isEmpty: Bool { right.isEmpty && left.isEmpty }

    init(right: Set<Int> = [], left: Set<Int> = []) {
        self.right = right
        self.left = left
    }

    init(startedContacts: [PianoKeyContactObservation]) {
        var right: Set<Int> = []
        var left: Set<Int> = []
        for contact in startedContacts where contact.phase == .started {
            guard let midiNote = contact.keyCandidate.exactMIDINote else { continue }
            switch contact.hand {
            case .right: right.insert(midiNote)
            case .left: left.insert(midiNote)
            }
        }
        self.right = right
        self.left = left
    }
}

protocol ChordAttemptAccumulatorProtocol {
    func register(
        pressedNotes: Set<Int>,
        expectedNotes: [Int],
        tolerance: Int,
        at timestamp: PerformanceMonotonicInstant
    ) -> StepAttemptMatchResult

    func registerHandSeparated(
        evidence: HandSeparatedNoteEvidence,
        expectedRightNotes: [Int],
        expectedLeftNotes: [Int],
        expectedUnassignedNotes: [Int],
        tolerance: Int,
        at timestamp: PerformanceMonotonicInstant
    ) -> StepAttemptMatchResult
    func reset()
}

extension ChordAttemptAccumulatorProtocol {
    func registerHandSeparated(
        evidence: HandSeparatedNoteEvidence,
        expectedRightNotes: [Int],
        expectedLeftNotes: [Int],
        expectedUnassignedNotes: [Int],
        tolerance: Int,
        at timestamp: PerformanceMonotonicInstant
    ) -> StepAttemptMatchResult {
        register(
            pressedNotes: evidence.all,
            expectedNotes: Set(expectedRightNotes + expectedLeftNotes + expectedUnassignedNotes).sorted(),
            tolerance: tolerance,
            at: timestamp
        )
    }
}

final class ChordAttemptAccumulator: ChordAttemptAccumulatorProtocol {
    private enum Hand: Hashable {
        case right
        case left
    }

    private struct HandNote: Hashable {
        let hand: Hand
        let midiNote: Int
    }

    private let simultaneousSpreadSeconds: TimeInterval
    private let rolledSpanSeconds: TimeInterval
    private let matcher: StepMatcherProtocol

    private var onsetByHandNote: [HandNote: PerformanceMonotonicInstant] = [:]

    init(
        windowSeconds: TimeInterval = 0.6,
        simultaneousSpreadSeconds: TimeInterval = 0.08,
        matcher: StepMatcherProtocol = StepMatcher()
    ) {
        rolledSpanSeconds = max(0, windowSeconds)
        self.simultaneousSpreadSeconds = max(0, simultaneousSpreadSeconds)
        self.matcher = matcher
    }

    func register(
        pressedNotes: Set<Int>,
        expectedNotes: [Int],
        tolerance: Int,
        at timestamp: PerformanceMonotonicInstant
    ) -> StepAttemptMatchResult {
        register(
            pressedNotes: pressedNotes,
            expectedNotes: expectedNotes,
            tolerance: tolerance,
            onsetExpectation: .rolled,
            at: timestamp
        )
    }

    func register(
        pressedNotes: Set<Int>,
        expectedNotes: [Int],
        tolerance: Int,
        onsetExpectation: ChordOnsetExpectation,
        at timestamp: PerformanceMonotonicInstant
    ) -> StepAttemptMatchResult {
        registerHandSeparated(
            evidence: HandSeparatedNoteEvidence(right: pressedNotes),
            expectedRightNotes: expectedNotes,
            expectedLeftNotes: [],
            expectedUnassignedNotes: [],
            tolerance: tolerance,
            onsetExpectation: onsetExpectation,
            at: timestamp
        )
    }

    func registerHandSeparated(
        evidence: HandSeparatedNoteEvidence,
        expectedRightNotes: [Int],
        expectedLeftNotes: [Int],
        expectedUnassignedNotes: [Int],
        tolerance: Int,
        at timestamp: PerformanceMonotonicInstant
    ) -> StepAttemptMatchResult {
        registerHandSeparated(
            evidence: evidence,
            expectedRightNotes: expectedRightNotes,
            expectedLeftNotes: expectedLeftNotes,
            expectedUnassignedNotes: expectedUnassignedNotes,
            tolerance: tolerance,
            onsetExpectation: .rolled,
            at: timestamp
        )
    }

    func registerHandSeparated(
        evidence: HandSeparatedNoteEvidence,
        expectedRightNotes: [Int],
        expectedLeftNotes: [Int],
        expectedUnassignedNotes: [Int],
        tolerance: Int,
        onsetExpectation: ChordOnsetExpectation,
        at timestamp: PerformanceMonotonicInstant
    ) -> StepAttemptMatchResult {
        let expectedUnion = Set(expectedRightNotes + expectedLeftNotes + expectedUnassignedNotes)
        guard evidence.isEmpty == false, expectedUnion.isEmpty == false else {
            return .insufficientEvidence
        }

        if let firstOnset = onsetByHandNote.values.min(),
           timestamp < firstOnset || timestamp.seconds - firstOnset.seconds > maximumSpan(for: onsetExpectation)
        {
            reset()
        }
        for note in evidence.right {
            onsetByHandNote[HandNote(hand: .right, midiNote: note)] =
                onsetByHandNote[HandNote(hand: .right, midiNote: note)] ?? timestamp
        }
        for note in evidence.left {
            onsetByHandNote[HandNote(hand: .left, midiNote: note)] =
                onsetByHandNote[HandNote(hand: .left, midiNote: note)] ?? timestamp
        }

        let observedRight = Set(onsetByHandNote.keys.lazy.compactMap {
            $0.hand == .right ? $0.midiNote : nil
        })
        let observedLeft = Set(onsetByHandNote.keys.lazy.compactMap {
            $0.hand == .left ? $0.midiNote : nil
        })
        let rightMatched = expectedRightNotes.isEmpty || matcher.matches(
            expectedNotes: expectedRightNotes,
            pressedNotes: observedRight,
            tolerance: tolerance
        )
        let leftMatched = expectedLeftNotes.isEmpty || matcher.matches(
            expectedNotes: expectedLeftNotes,
            pressedNotes: observedLeft,
            tolerance: tolerance
        )
        let unassignedMatched = expectedUnassignedNotes.isEmpty || matcher.matches(
            expectedNotes: expectedUnassignedNotes,
            pressedNotes: observedRight.union(observedLeft),
            tolerance: tolerance
        )

        guard rightMatched, leftMatched, unassignedMatched else { return .insufficientEvidence }
        guard onsetSpread <= maximumSpan(for: onsetExpectation) else {
            reset(keeping: evidence, at: timestamp)
            return .insufficientEvidence
        }

        reset()
        return .matched
    }

    func reset() {
        onsetByHandNote.removeAll(keepingCapacity: true)
    }

    private var onsetSpread: TimeInterval {
        guard let first = onsetByHandNote.values.min(), let last = onsetByHandNote.values.max() else { return 0 }
        return last.seconds - first.seconds
    }

    private func maximumSpan(for expectation: ChordOnsetExpectation) -> TimeInterval {
        switch expectation {
        case .simultaneous:
            simultaneousSpreadSeconds
        case .rolled:
            rolledSpanSeconds
        }
    }

    private func reset(keeping evidence: HandSeparatedNoteEvidence, at timestamp: PerformanceMonotonicInstant) {
        reset()
        for note in evidence.right {
            onsetByHandNote[HandNote(hand: .right, midiNote: note)] = timestamp
        }
        for note in evidence.left {
            onsetByHandNote[HandNote(hand: .left, midiNote: note)] = timestamp
        }
    }
}
