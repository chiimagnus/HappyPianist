import Foundation


public struct MusicXMLHandRoutingResult: Equatable {
    public let assignmentsBySourceNoteID: [MusicXMLSourceNoteID: ScoreHandAssignment]

    public func assignment(for note: MusicXMLNoteEvent) -> ScoreHandAssignment {
        guard let sourceID = note.sourceID else { return .unknown }
        return assignmentsBySourceNoteID[sourceID] ?? .unknown
    }
}

public struct MusicXMLHandRouter {
    private let minimumRegisterSpan = 12
    private let minimumSplitGap = 5
    private let uncertaintyRadius = 1

    public func assignments(for score: MusicXMLScore) -> MusicXMLHandRoutingResult {
        let pitchedNotes = score.notes.filter { note in
            note.isRest == false && note.midiNote != nil
        }
        guard pitchedNotes.isEmpty == false else {
            return MusicXMLHandRoutingResult(assignmentsBySourceNoteID: [:])
        }

        let hasMultipleStaves = pitchedNotes.contains { ($0.staff ?? 1) > 1 }
        guard hasMultipleStaves == false else {
            return MusicXMLHandRoutingResult(assignmentsBySourceNoteID: [:])
        }

        let uniquePitches = Array(Set(pitchedNotes.compactMap(\.midiNote))).sorted()
        guard let lowest = uniquePitches.first,
              let highest = uniquePitches.last,
              highest - lowest >= minimumRegisterSpan,
              let split = clearestSplit(in: uniquePitches),
              let uncertaintyBoundary = centralBoundary(in: uniquePitches)
        else {
            return MusicXMLHandRoutingResult(assignmentsBySourceNoteID: [:])
        }

        var assignments: [MusicXMLSourceNoteID: ScoreHandAssignment] = [:]
        assignments.reserveCapacity(pitchedNotes.count)
        for note in pitchedNotes {
            guard let sourceID = note.sourceID, let midiNote = note.midiNote else { continue }
            // ponytail: keep the score's central pitches unknown until explicit fingering evidence exists.
            let uncertaintyDistance = abs(Double(midiNote) - uncertaintyBoundary)
            guard uncertaintyDistance > Double(uncertaintyRadius) else {
                assignments[sourceID] = .unknown
                continue
            }
            let hand: ScoreHand = Double(midiNote) < split.boundary ? .left : .right
            let distance = abs(Double(midiNote) - split.boundary)
            let confidence = min(0.98, 0.55 + distance / 24)
            assignments[sourceID] = ScoreHandAssignment(
                hand: hand,
                provenance: .heuristic,
                confidence: confidence
            )
        }

        return MusicXMLHandRoutingResult(assignmentsBySourceNoteID: assignments)
    }

    private func clearestSplit(in pitches: [Int]) -> (boundary: Double, gap: Int)? {
        guard pitches.count >= 2 else { return nil }
        let candidates = zip(pitches, pitches.dropFirst()).map { lower, upper in
            (lower: lower, upper: upper, gap: upper - lower)
        }
        guard let best = candidates.max(by: { lhs, rhs in
            if lhs.gap != rhs.gap { return lhs.gap < rhs.gap }
            return lhs.lower < rhs.lower
        }), best.gap >= minimumSplitGap
        else { return nil }
        return (boundary: Double(best.lower + best.upper) / 2, gap: best.gap)
    }

    private func centralBoundary(in pitches: [Int]) -> Double? {
        guard pitches.isEmpty == false else { return nil }
        let middle = pitches.count / 2
        guard pitches.count.isMultiple(of: 2) else { return Double(pitches[middle]) }
        return Double(pitches[middle - 1] + pitches[middle]) / 2
    }
}
