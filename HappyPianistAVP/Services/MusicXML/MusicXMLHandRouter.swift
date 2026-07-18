import Foundation

struct MusicXMLHandRoutingResult: Equatable, Sendable {
    let assignmentsBySourceNoteID: [MusicXMLSourceNoteID: ScoreHandAssignment]

    func assignment(for note: MusicXMLNoteEvent) -> ScoreHandAssignment {
        guard let sourceID = note.sourceID else { return .unknown }
        return assignmentsBySourceNoteID[sourceID] ?? .unknown
    }
}

struct MusicXMLHandRouter {
    private let minimumRegisterSpan = 12
    private let minimumSplitGap = 5
    private let uncertaintyRadius = 2

    func assignments(for score: MusicXMLScore) -> MusicXMLHandRoutingResult {
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
              let split = clearestSplit(in: uniquePitches)
        else {
            return MusicXMLHandRoutingResult(assignmentsBySourceNoteID: [:])
        }

        var assignments: [MusicXMLSourceNoteID: ScoreHandAssignment] = [:]
        assignments.reserveCapacity(pitchedNotes.count)
        for note in pitchedNotes {
            guard let sourceID = note.sourceID, let midiNote = note.midiNote else { continue }
            let distance = abs(Double(midiNote) - split.boundary)
            guard distance > Double(uncertaintyRadius) else {
                assignments[sourceID] = .unknown
                continue
            }
            let hand: ScoreHand = Double(midiNote) < split.boundary ? .left : .right
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
}
