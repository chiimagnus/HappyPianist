import CoreGraphics

struct GrandStaffChordLayoutService {
    struct Note: Equatable {
        let id: String
        let staffNumber: Int
        let staffStep: Int
        let voice: Int
        let sourceStem: MusicXMLStem
    }

    struct Chord: Equatable {
        let id: String
        let tick: Int
        let notes: [Note]
    }

    struct Layout: Equatable {
        let chordID: String
        let direction: GrandStaffStemDirection
        let isStemVisible: Bool
        let noteheadXOffsets: [String: Double]
        let stemStartItemID: String
        let stemEndItemID: String
        let stemXOffset: Double
    }

    struct StemGeometry: Equatable {
        let start: CGPoint
        let end: CGPoint
    }

    private struct PlacedNote {
        let tick: Int
        let staffNumber: Int
        let staffStep: Int
        let xOffset: Double
    }

    private let collisionStep = 1.15

    func makeLayouts(chords: [Chord]) -> [Layout] {
        let sortedChords = chords.sorted { lhs, rhs in
            if lhs.tick != rhs.tick { return lhs.tick < rhs.tick }
            let lhsVoice = lhs.notes.map(\.voice).min() ?? 1
            let rhsVoice = rhs.notes.map(\.voice).min() ?? 1
            if lhsVoice != rhsVoice { return lhsVoice < rhsVoice }
            return lhs.id < rhs.id
        }
        var placedNotes: [PlacedNote] = []
        var layouts: [Layout] = []
        layouts.reserveCapacity(sortedChords.count)

        for chord in sortedChords where chord.notes.isEmpty == false {
            let direction = resolvedDirection(for: chord, among: sortedChords)
            let internalOffsets = noteheadOffsets(for: chord.notes, direction: direction)
            let collisionShift = resolvedCollisionShift(
                chord: chord,
                internalOffsets: internalOffsets,
                placedNotes: placedNotes
            )
            let offsets = internalOffsets.mapValues { $0 + collisionShift }
            let highToLow = chord.notes.sorted(by: isVisuallyHigher)
            guard let highest = highToLow.first, let lowest = highToLow.last else { continue }
            let start = direction == .up ? lowest : highest
            let end = direction == .up ? highest : lowest
            let attachmentOffset = direction == .up ? 0.5 : -0.5

            layouts.append(Layout(
                chordID: chord.id,
                direction: direction,
                isStemVisible: chord.notes.contains { $0.sourceStem == .none } == false,
                noteheadXOffsets: offsets,
                stemStartItemID: start.id,
                stemEndItemID: end.id,
                stemXOffset: collisionShift + attachmentOffset
            ))

            placedNotes.append(contentsOf: chord.notes.map {
                PlacedNote(
                    tick: chord.tick,
                    staffNumber: $0.staffNumber,
                    staffStep: $0.staffStep,
                    xOffset: offsets[$0.id] ?? collisionShift
                )
            })
        }
        return layouts
    }

    func stemGeometry(
        stem: GrandStaffNotationStem,
        chordX: CGFloat,
        noteheadWidth: CGFloat,
        stemLength: CGFloat,
        noteCentersByID: [String: CGPoint]
    ) -> StemGeometry? {
        guard let startCenter = noteCentersByID[stem.startItemID],
              let endCenter = noteCentersByID[stem.endItemID]
        else { return nil }
        let x = chordX + stem.xOffset * noteheadWidth
        let endY = endCenter.y + (stem.direction == .up ? -stemLength : stemLength)
        return StemGeometry(
            start: CGPoint(x: x, y: startCenter.y),
            end: CGPoint(x: x, y: endY)
        )
    }

    private func resolvedDirection(for chord: Chord, among chords: [Chord]) -> GrandStaffStemDirection {
        for note in chord.notes.sorted(by: { $0.id < $1.id }) {
            switch note.sourceStem {
            case .up: return .up
            case .down: return .down
            default: continue
            }
        }

        let occupiedStaves = Set(chord.notes.map(\.staffNumber))
        let voicesAtTick = Set(chords.lazy
            .filter { candidate in
                candidate.tick == chord.tick &&
                    occupiedStaves.isDisjoint(with: candidate.notes.map(\.staffNumber)) == false
            }
            .flatMap { $0.notes.map(\.voice) })
        let voice = chord.notes.map(\.voice).min() ?? 1
        if voicesAtTick.count > 1 {
            // ponytail: conventional four-voice parity; add explicit voice roles if >4-voice engraving matters.
            return voice.isMultiple(of: 2) ? .down : .up
        }

        let averageStaffStep = chord.notes.map { Double($0.staffStep) }.reduce(0, +)
            / Double(max(1, chord.notes.count))
        return averageStaffStep >= 4 ? .down : .up
    }

    private func noteheadOffsets(
        for notes: [Note],
        direction: GrandStaffStemDirection
    ) -> [String: Double] {
        var offsets: [String: Double] = [:]
        for staffNotes in Dictionary(grouping: notes, by: \.staffNumber).values {
            let ordered = staffNotes.sorted { lhs, rhs in
                if lhs.staffStep != rhs.staffStep {
                    return direction == .up
                        ? lhs.staffStep < rhs.staffStep
                        : lhs.staffStep > rhs.staffStep
                }
                return lhs.id < rhs.id
            }
            var previousStep: Int?
            var displaced = false
            for note in ordered {
                if let previousStep, abs(note.staffStep - previousStep) <= 1 {
                    displaced.toggle()
                } else {
                    displaced = false
                }
                offsets[note.id] = displaced ? (direction == .up ? 1 : -1) : 0
                previousStep = note.staffStep
            }
        }
        return offsets
    }

    private func resolvedCollisionShift(
        chord: Chord,
        internalOffsets: [String: Double],
        placedNotes: [PlacedNote]
    ) -> Double {
        let relevantNotes = placedNotes.filter { $0.tick == chord.tick }
        guard relevantNotes.isEmpty == false else { return 0 }

        for distance in 0 ... relevantNotes.count + 1 {
            let candidates = distance == 0
                ? [0.0]
                : [Double(distance) * collisionStep, -Double(distance) * collisionStep]
            if let shift = candidates.first(where: { candidate in
                chord.notes.allSatisfy { note in
                    let xOffset = (internalOffsets[note.id] ?? 0) + candidate
                    return relevantNotes.allSatisfy { placed in
                        placed.staffNumber != note.staffNumber ||
                            abs(placed.staffStep - note.staffStep) > 1 ||
                            abs(placed.xOffset - xOffset) >= collisionStep
                    }
                }
            }) {
                return shift
            }
        }
        return Double(relevantNotes.count + 2) * collisionStep
    }

    private func isVisuallyHigher(_ lhs: Note, _ rhs: Note) -> Bool {
        if lhs.staffNumber != rhs.staffNumber { return lhs.staffNumber < rhs.staffNumber }
        if lhs.staffStep != rhs.staffStep { return lhs.staffStep > rhs.staffStep }
        return lhs.id < rhs.id
    }
}
