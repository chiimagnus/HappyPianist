import Foundation

final class MIDIPracticeStepMatcher {
    struct Configuration: Equatable {
        var chordWindow: TimeInterval = 0.18
        var rearmSilenceWindow: TimeInterval = 0.08
        var noteOffRequired: Bool = false
    }

    private(set) var configuration: Configuration

    private var stepIndex: Int = -1
    private var expectedRight: Set<Int> = []
    private var expectedLeft: Set<Int> = []
    private var expectedUnion: Set<Int> = []
    private var windowStart: Date?
    private var accumulatedNotes: Set<Int> = []
    private var rearmBlockedUntil: [Int: Date] = [:]

    init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    func reset(stepIndex: Int, expectedNotes: [PracticeStepNote], configuredAt now: Date) {
        self.stepIndex = stepIndex
        expectedRight.removeAll(keepingCapacity: true)
        expectedLeft.removeAll(keepingCapacity: true)

        for note in expectedNotes {
            if note.hand == .left {
                expectedLeft.insert(note.midiNote)
            } else {
                expectedRight.insert(note.midiNote)
            }
        }
        expectedUnion = expectedRight.union(expectedLeft)
        windowStart = nil
        accumulatedNotes.removeAll(keepingCapacity: true)
        rearmBlockedUntil.removeAll(keepingCapacity: true)
        pruneRearm(now: now)
    }

    func registerNoteOn(note: Int, at timestamp: Date) -> StepAttemptMatchResult {
        guard expectedUnion.isEmpty == false else {
            return .insufficient(progress: "no expected notes")
        }

        pruneRearm(now: timestamp)
        guard isRearmSatisfied(note: note, at: timestamp) else {
            return .insufficient(progress: "rearm blocked")
        }

        if windowStart == nil {
            windowStart = timestamp
            accumulatedNotes.removeAll(keepingCapacity: true)
        }

        if let windowStart, timestamp.timeIntervalSince(windowStart) > configuration.chordWindow {
            self.windowStart = timestamp
            accumulatedNotes.removeAll(keepingCapacity: true)
        }

        if expectedUnion.contains(note) {
            accumulatedNotes.insert(note)
        } else {
            return .wrong(reason: "unexpected note")
        }

        return evaluate(at: timestamp)
    }

    func registerNoteOff(note: Int, at timestamp: Date) {
        guard configuration.noteOffRequired else { return }
        rearmBlockedUntil[note] = timestamp.addingTimeInterval(configuration.rearmSilenceWindow)
    }

    private func evaluate(at timestamp: Date) -> StepAttemptMatchResult {
        func isSatisfied(expected: Set<Int>, accumulated: Set<Int>) -> (Bool, String?) {
            guard expected.isEmpty == false else { return (true, nil) }
            if expected.count == 1 {
                let note = expected.first!
                return accumulated.contains(note) ? (true, nil) : (false, "single pending")
            }
            let matched = expected.intersection(accumulated).count
            return matched == expected.count ? (true, nil) : (false, "\(matched)/\(expected.count)")
        }

        let right = isSatisfied(expected: expectedRight, accumulated: accumulatedNotes)
        let left = isSatisfied(expected: expectedLeft, accumulated: accumulatedNotes)

        if right.0, left.0 {
            for note in expectedUnion {
                rearmBlockedUntil[note] = timestamp.addingTimeInterval(configuration.rearmSilenceWindow)
            }
            return .matched(reason: "midi deterministic matched")
        }

        var progressItems: [String] = []
        if right.0 == false, let p = right.1 { progressItems.append("R \(p)") }
        if left.0 == false, let p = left.1 { progressItems.append("L \(p)") }
        if expectedRight.isEmpty && expectedLeft.isEmpty == false {
            return .insufficient(progress: progressItems.joined(separator: " "))
        }
        if expectedLeft.isEmpty && expectedRight.isEmpty == false {
            return .insufficient(progress: progressItems.joined(separator: " "))
        }

        let required = expectedUnion.count
        let matched = expectedUnion.intersection(accumulatedNotes).count
        return .insufficient(progress: "chord \(matched)/\(required)")
    }

    private func isRearmSatisfied(note: Int, at timestamp: Date) -> Bool {
        guard let blockedUntil = rearmBlockedUntil[note] else { return true }
        return timestamp >= blockedUntil
    }

    private func pruneRearm(now: Date) {
        rearmBlockedUntil = rearmBlockedUntil.filter { _, blockedUntil in
            blockedUntil > now
        }
    }
}

