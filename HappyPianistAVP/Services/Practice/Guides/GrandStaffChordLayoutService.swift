import CoreGraphics

struct GrandStaffChordLayoutService {
    struct Note: Equatable {
        let id: String
        let staffNumber: Int
        let staffStep: Int
        let voice: Int
        let sourceStem: MusicXMLStem
        let noteheadToken: GrandStaffGlyphToken?
        let accidentalToken: GrandStaffGlyphToken?
        let dotCount: Int
        let isGrace: Bool
        let ledgerStaffSteps: [Int]

        init(
            id: String,
            staffNumber: Int,
            staffStep: Int,
            voice: Int,
            sourceStem: MusicXMLStem,
            noteheadToken: GrandStaffGlyphToken? = .noteheadBlack,
            accidentalToken: GrandStaffGlyphToken? = nil,
            dotCount: Int = 0,
            isGrace: Bool = false,
            ledgerStaffSteps: [Int] = []
        ) {
            self.id = id
            self.staffNumber = staffNumber
            self.staffStep = staffStep
            self.voice = voice
            self.sourceStem = sourceStem
            self.noteheadToken = noteheadToken
            self.accidentalToken = accidentalToken
            self.dotCount = dotCount
            self.isGrace = isGrace
            self.ledgerStaffSteps = ledgerStaffSteps
        }
    }

    struct Chord: Equatable {
        let id: String
        let tick: Int
        let xPosition: Double
        let notes: [Note]

        init(id: String, tick: Int, xPosition: Double = 0.5, notes: [Note]) {
            self.id = id
            self.tick = tick
            self.xPosition = xPosition
            self.notes = notes
        }
    }

    struct DotLayout: Equatable {
        let xOffsetStaffSpaces: Double
        let staffStep: Int
    }

    struct LedgerLine: Equatable {
        let id: String
        let tick: Int
        let xPosition: Double
        let staffNumber: Int
        let staffStep: Int
        let minXOffsetStaffSpaces: Double
        let maxXOffsetStaffSpaces: Double
    }

    struct Layout: Equatable {
        let chordID: String
        let direction: GrandStaffStemDirection
        let isStemVisible: Bool
        let noteheadXOffsets: [String: Double]
        let accidentalXOffsetsStaffSpaces: [String: Double]
        let dotLayouts: [String: DotLayout]
        let stemStartItemID: String
        let stemEndItemID: String
        let stemXOffset: Double
    }

    struct Result: Equatable {
        let chords: [Layout]
        let ledgerLines: [LedgerLine]
    }

    struct StemGeometry: Equatable {
        let start: CGPoint
        let end: CGPoint
    }

    private struct Rect {
        let minX: Double
        let minY: Double
        let maxX: Double
        let maxY: Double

        func intersects(_ other: Rect) -> Bool {
            minX < other.maxX && maxX > other.minX && minY < other.maxY && maxY > other.minY
        }
    }

    private struct PlacedNote {
        let staffNumber: Int
        let rect: Rect
    }

    private struct NotePlacement {
        let chordID: String
        let chordXPosition: Double
        let tick: Int
        let note: Note
        let centerX: Double
        let rect: Rect
    }

    private struct PlacedMark {
        let rect: Rect
    }

    private struct LedgerKey: Hashable {
        let tick: Int
        let staffNumber: Int
        let staffStep: Int
    }

    private struct TickStaffKey: Hashable {
        let tick: Int
        let staffNumber: Int
    }

    private struct BaseLayout {
        let chord: Chord
        let direction: GrandStaffStemDirection
        let isStemVisible: Bool
        let noteheadXOffsets: [String: Double]
        let stemStartItemID: String
        let stemEndItemID: String
        let stemXOffset: Double
    }

    private let collisionStep = 1.15
    private let metrics: GrandStaffEngravingMetrics

    init(metrics: GrandStaffEngravingMetrics = GrandStaffEngravingMetrics()) {
        self.metrics = metrics
    }

    func makeLayout(chords: [Chord]) -> Result {
        let sortedChords = chords.sorted { lhs, rhs in
            if lhs.tick != rhs.tick { return lhs.tick < rhs.tick }
            let lhsVoice = lhs.notes.map(\.voice).min() ?? 1
            let rhsVoice = rhs.notes.map(\.voice).min() ?? 1
            if lhsVoice != rhsVoice { return lhsVoice < rhsVoice }
            return lhs.id < rhs.id
        }
        let chordsByTick = Dictionary(grouping: sortedChords, by: \.tick)
        var placedNotesByTick: [Int: [PlacedNote]] = [:]
        var baseLayouts: [BaseLayout] = []
        baseLayouts.reserveCapacity(sortedChords.count)

        for chord in sortedChords where chord.notes.isEmpty == false {
            let direction = resolvedDirection(for: chord, among: chordsByTick[chord.tick] ?? [])
            let internalOffsets = noteheadOffsets(for: chord.notes, direction: direction)
            let collisionShift = resolvedCollisionShift(
                chord: chord,
                internalOffsets: internalOffsets,
                placedNotes: placedNotesByTick[chord.tick] ?? []
            )
            let offsets = internalOffsets.mapValues { $0 + collisionShift }
            let highToLow = chord.notes.sorted(by: isVisuallyHigher)
            guard let highest = highToLow.first, let lowest = highToLow.last else { continue }
            let start = direction == .up ? lowest : highest
            let end = direction == .up ? highest : lowest
            let attachmentOffset = direction == .up ? 0.5 : -0.5

            baseLayouts.append(BaseLayout(
                chord: chord,
                direction: direction,
                isStemVisible: chord.notes.contains { $0.sourceStem == .none } == false,
                noteheadXOffsets: offsets,
                stemStartItemID: start.id,
                stemEndItemID: end.id,
                stemXOffset: collisionShift + attachmentOffset
            ))
            placedNotesByTick[chord.tick, default: []].append(contentsOf: chord.notes.map {
                PlacedNote(
                    staffNumber: $0.staffNumber,
                    rect: noteheadRect(note: $0, xOffset: offsets[$0.id] ?? collisionShift)
                )
            })
        }

        let notePlacements = baseLayouts.flatMap(makeNotePlacements)
        let accidentalOffsets = accidentalOffsets(notePlacements: notePlacements)
        let dotLayouts = dotLayouts(baseLayouts: baseLayouts, notePlacements: notePlacements)
        let ledgerLines = ledgerLines(notePlacements: notePlacements)
        let layouts = baseLayouts.map { base in
            Layout(
                chordID: base.chord.id,
                direction: base.direction,
                isStemVisible: base.isStemVisible,
                noteheadXOffsets: base.noteheadXOffsets,
                accidentalXOffsetsStaffSpaces: accidentalOffsets[base.chord.id] ?? [:],
                dotLayouts: dotLayouts[base.chord.id] ?? [:],
                stemStartItemID: base.stemStartItemID,
                stemEndItemID: base.stemEndItemID,
                stemXOffset: base.stemXOffset
            )
        }
        return Result(chords: layouts, ledgerLines: ledgerLines)
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

    private func makeNotePlacements(base: BaseLayout) -> [NotePlacement] {
        base.chord.notes.map { note in
            let centerX = noteheadCenterX(note: note, xOffset: base.noteheadXOffsets[note.id] ?? 0)
            return NotePlacement(
                chordID: base.chord.id,
                chordXPosition: base.chord.xPosition,
                tick: base.chord.tick,
                note: note,
                centerX: centerX,
                rect: noteheadRect(note: note, centerX: centerX)
            )
        }
    }

    private func accidentalOffsets(notePlacements: [NotePlacement]) -> [String: [String: Double]] {
        var result: [String: [String: Double]] = [:]
        let groups = Dictionary(grouping: notePlacements) {
            TickStaffKey(tick: $0.tick, staffNumber: $0.note.staffNumber)
        }
        let sortedKeys = groups.keys.sorted {
            $0.tick == $1.tick ? $0.staffNumber < $1.staffNumber : $0.tick < $1.tick
        }
        for key in sortedKeys {
            let groupNotes = groups[key] ?? []
            let accidentalPlacements = groupNotes.filter { $0.note.accidentalToken != nil }.sorted {
                if $0.note.staffStep != $1.note.staffStep { return $0.note.staffStep > $1.note.staffStep }
                if $0.note.voice != $1.note.voice { return $0.note.voice < $1.note.voice }
                return $0.note.id < $1.note.id
            }
            let maximumWidth = accidentalPlacements
                .compactMap { $0.note.accidentalToken.flatMap(metrics.bounds) }
                .map(\.width)
                .max() ?? 0
            let baseRight = (groupNotes.map(\.rect.minX).min() ?? 0) - metrics.accidentalNoteheadGap
            var placedMarks: [PlacedMark] = []

            for placement in accidentalPlacements {
                guard let token = placement.note.accidentalToken,
                      let bounds = metrics.bounds(for: token)
                else { continue }
                let scale = metrics.glyphScale(isGrace: placement.note.isGrace)
                let centerY = Double(placement.note.staffStep) / 2
                for column in 0 ... placedMarks.count + 1 {
                    let right = baseRight - Double(column) * (maximumWidth + metrics.accidentalColumnGap)
                    let centerX = right - bounds.maxX * scale
                    let rect = Rect(
                        minX: centerX + bounds.minX * scale,
                        minY: centerY + bounds.minY * scale,
                        maxX: centerX + bounds.maxX * scale,
                        maxY: centerY + bounds.maxY * scale
                    )
                    if placedMarks.contains(where: { $0.rect.intersects(rect) }) == false {
                        result[placement.chordID, default: [:]][placement.note.id] = centerX
                        placedMarks.append(PlacedMark(
                            rect: rect
                        ))
                        break
                    }
                }
            }
        }
        return result
    }

    private func dotLayouts(
        baseLayouts: [BaseLayout],
        notePlacements: [NotePlacement]
    ) -> [String: [String: DotLayout]] {
        guard let dotBounds = metrics.bounds(for: .augmentationDot) else { return [:] }
        let directionByChordID = Dictionary(uniqueKeysWithValues: baseLayouts.map { ($0.chord.id, $0.direction) })
        var result: [String: [String: DotLayout]] = [:]
        let groups = Dictionary(grouping: notePlacements) {
            TickStaffKey(tick: $0.tick, staffNumber: $0.note.staffNumber)
        }
        let sortedKeys = groups.keys.sorted {
            $0.tick == $1.tick ? $0.staffNumber < $1.staffNumber : $0.tick < $1.tick
        }
        for key in sortedKeys {
            let groupNotes = groups[key] ?? []
            let dottedNotes = groupNotes.filter { $0.note.dotCount > 0 }.sorted {
                if $0.note.voice != $1.note.voice { return $0.note.voice < $1.note.voice }
                if $0.note.staffStep != $1.note.staffStep { return $0.note.staffStep < $1.note.staffStep }
                return $0.note.id < $1.note.id
            }
            let rightmostNote = groupNotes.map(\.rect.maxX).max() ?? 0
            let centerX = rightmostNote + metrics.dotNoteheadGap - dotBounds.minX
            var placedDots: [PlacedMark] = []

            for placement in dottedNotes {
                let direction = directionByChordID[placement.chordID] ?? .up
                let verticalDirection = direction == .up ? 1 : -1
                let initialStep = placement.note.staffStep.isMultiple(of: 2)
                    ? placement.note.staffStep + verticalDirection
                    : placement.note.staffStep
                for attempt in 0 ... placedDots.count + 1 {
                    let staffStep = initialStep + attempt * 2 * verticalDirection
                    let centerY = Double(staffStep) / 2
                    let rect = Rect(
                        minX: centerX + dotBounds.minX,
                        minY: centerY + dotBounds.minY,
                        maxX: centerX + dotBounds.maxX
                            + Double(max(0, placement.note.dotCount - 1)) * metrics.dotSpacing,
                        maxY: centerY + dotBounds.maxY
                    )
                    if placedDots.contains(where: { $0.rect.intersects(rect) }) == false {
                        result[placement.chordID, default: [:]][placement.note.id] = DotLayout(
                            xOffsetStaffSpaces: centerX,
                            staffStep: staffStep
                        )
                        placedDots.append(PlacedMark(
                            rect: rect
                        ))
                        break
                    }
                }
            }
        }
        return result
    }

    private func ledgerLines(notePlacements: [NotePlacement]) -> [LedgerLine] {
        var segments: [LedgerKey: (xPosition: Double, minX: Double, maxX: Double)] = [:]
        for placement in notePlacements {
            let bounds = placement.note.noteheadToken.flatMap(metrics.bounds) ?? metrics.noteheadViewportBounds
            let scale = metrics.glyphScale(isGrace: placement.note.isGrace)
            for staffStep in placement.note.ledgerStaffSteps {
                let key = LedgerKey(
                    tick: placement.tick,
                    staffNumber: placement.note.staffNumber,
                    staffStep: staffStep
                )
                let minX = placement.centerX + bounds.minX * scale - metrics.ledgerLineExtension
                let maxX = placement.centerX + bounds.maxX * scale + metrics.ledgerLineExtension
                if let existing = segments[key] {
                    segments[key] = (
                        xPosition: existing.xPosition,
                        minX: min(existing.minX, minX),
                        maxX: max(existing.maxX, maxX)
                    )
                } else {
                    segments[key] = (placement.chordXPosition, minX, maxX)
                }
            }
        }
        return segments.keys.sorted {
            if $0.tick != $1.tick { return $0.tick < $1.tick }
            if $0.staffNumber != $1.staffNumber { return $0.staffNumber < $1.staffNumber }
            return $0.staffStep < $1.staffStep
        }.compactMap { key in
            guard let segment = segments[key] else { return nil }
            return LedgerLine(
                id: "ledger-\(key.tick)-\(key.staffNumber)-\(key.staffStep)",
                tick: key.tick,
                xPosition: segment.xPosition,
                staffNumber: key.staffNumber,
                staffStep: key.staffStep,
                minXOffsetStaffSpaces: segment.minX,
                maxXOffsetStaffSpaces: segment.maxX
            )
        }
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
        guard placedNotes.isEmpty == false else { return 0 }

        for distance in 0 ... placedNotes.count + 1 {
            let candidates = distance == 0
                ? [0.0]
                : [Double(distance) * collisionStep, -Double(distance) * collisionStep]
            if let shift = candidates.first(where: { candidate in
                chord.notes.allSatisfy { note in
                    let rect = noteheadRect(
                        note: note,
                        xOffset: (internalOffsets[note.id] ?? 0) + candidate
                    )
                    return placedNotes.allSatisfy { placed in
                        placed.staffNumber != note.staffNumber || placed.rect.intersects(rect) == false
                    }
                }
            }) {
                return shift
            }
        }
        return Double(placedNotes.count + 2) * collisionStep
    }

    private func noteheadCenterX(note: Note, xOffset: Double) -> Double {
        xOffset * metrics.noteheadColumnWidth * metrics.glyphScale(isGrace: note.isGrace)
    }

    private func noteheadRect(note: Note, xOffset: Double) -> Rect {
        noteheadRect(note: note, centerX: noteheadCenterX(note: note, xOffset: xOffset))
    }

    private func noteheadRect(note: Note, centerX: Double) -> Rect {
        // ponytail: unknown glyphs reserve one neutral notehead box; add a real token before changing visible engraving.
        let bounds = note.noteheadToken.flatMap(metrics.bounds) ?? metrics.noteheadViewportBounds
        let scale = metrics.glyphScale(isGrace: note.isGrace)
        let centerY = Double(note.staffStep) / 2
        return Rect(
            minX: centerX + bounds.minX * scale,
            minY: centerY + bounds.minY * scale,
            maxX: centerX + bounds.maxX * scale,
            maxY: centerY + bounds.maxY * scale
        )
    }

    private func isVisuallyHigher(_ lhs: Note, _ rhs: Note) -> Bool {
        if lhs.staffNumber != rhs.staffNumber { return lhs.staffNumber < rhs.staffNumber }
        if lhs.staffStep != rhs.staffStep { return lhs.staffStep > rhs.staffStep }
        return lhs.id < rhs.id
    }
}
