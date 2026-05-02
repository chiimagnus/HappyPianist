import Foundation

struct ScrollingStaffNotationLayoutService {
    private let visibleOverscan: Double = 0.18
    private let trebleBottomLineMIDINote = 64
    private let bassBottomLineMIDINote = 43
    private let blackKeyPitchClasses: Set<Int> = [1, 3, 6, 8, 10]
    private let diatonicIndexByPitchClass: [Int: Int] = [
        0: 0,
        1: 0,
        2: 1,
        3: 1,
        4: 2,
        5: 3,
        6: 3,
        7: 4,
        8: 4,
        9: 5,
        10: 5,
        11: 6,
    ]

    func makeItems(
        guides: [PianoHighlightGuide],
        currentGuide: PianoHighlightGuide?,
        halfWindowTicks: Int = 1_920
    ) -> [ScrollingStaffNotationItem] {
        makeLayout(
            guides: guides,
            currentGuide: currentGuide,
            halfWindowTicks: halfWindowTicks
        ).items
    }

    func makeLayout(
        guides: [PianoHighlightGuide],
        currentGuide: PianoHighlightGuide?,
        measureSpans: [MusicXMLMeasureSpan] = [],
        context: ScrollingStaffNotationContext? = nil,
        halfWindowTicks: Int = 1_920
    ) -> ScrollingStaffNotationLayout {
        guard guides.isEmpty == false else {
            return ScrollingStaffNotationLayout(
                items: [],
                chords: [],
                rests: [],
                barlines: [],
                beams: [],
                context: context
            )
        }

        let currentTick = currentGuide?.tick ?? guides.first?.tick ?? 0
        let safeHalfWindowTicks = max(1, halfWindowTicks)
        let currentGuideID = currentGuide?.id

        let rawItems = guides.flatMap { guide in
            guide.triggeredNotes.map { note in
                let xPosition = 0.5 + Double(guide.tick - currentTick) / Double(safeHalfWindowTicks * 2)
                return ScrollingStaffNotationItem(
                    occurrenceID: note.occurrenceID,
                    midiNote: note.midiNote,
                    guideID: guide.id,
                    tick: guide.tick,
                    xPosition: xPosition,
                    staff: note.staff,
                    voice: note.voice,
                    staffStep: staffStep(for: note.midiNote, staff: note.staff),
                    showsSharpAccidental: showsSharpAccidental(for: note.midiNote),
                    isHighlighted: guide.id == currentGuideID,
                    fingeringText: note.fingeringText,
                    noteValue: noteValue(forDurationTicks: max(1, note.offTick - note.onTick)),
                    chordID: nil,
                    noteHeadXOffset: 0,
                    stemDirection: .up,
                    beamID: nil,
                    durationTicks: max(1, note.offTick - note.onTick),
                    isGrace: note.isGrace,
                    tieStart: note.tieStart,
                    tieStop: note.tieStop,
                    tieEndXPosition: nil,
                    articulations: note.articulations,
                    arpeggiate: note.arpeggiate,
                    dotCount: note.dotCount
                )
            }
        }
        .filter { item in
            item.xPosition >= -visibleOverscan && item.xPosition <= 1 + visibleOverscan
        }
        .sorted { lhs, rhs in
            if lhs.tick != rhs.tick { return lhs.tick < rhs.tick }
            if lhs.midiNote != rhs.midiNote { return lhs.midiNote < rhs.midiNote }
            return lhs.occurrenceID < rhs.occurrenceID
        }

        let chordLayout = makeChordLayout(items: rawItems)
        let beamLayout = makeBeamLayout(items: chordLayout.items, chords: chordLayout.chords)
        let tiedItems = makeTieLayout(items: beamLayout.items)
        let rests = makeRests(
            guides: guides,
            currentTick: currentTick,
            currentGuideID: currentGuideID,
            safeHalfWindowTicks: safeHalfWindowTicks
        )
        let barlines = makeBarlines(
            measureSpans: measureSpans,
            currentTick: currentTick,
            safeHalfWindowTicks: safeHalfWindowTicks
        )

        return ScrollingStaffNotationLayout(
            items: tiedItems,
            chords: beamLayout.chords,
            rests: rests,
            barlines: barlines,
            beams: beamLayout.beams,
            context: context
        )
    }

    func staffStep(for midiNote: Int) -> Int {
        staffStep(for: midiNote, staff: 1)
    }

    func staffStep(for midiNote: Int, staff: Int?) -> Int {
        let bottomLineMIDINote = staff == 2 ? bassBottomLineMIDINote : trebleBottomLineMIDINote
        return diatonicIndex(for: midiNote) - diatonicIndex(for: bottomLineMIDINote)
    }

    func showsSharpAccidental(for midiNote: Int) -> Bool {
        blackKeyPitchClasses.contains(normalizedPitchClass(for: midiNote))
    }

    func ledgerStaffSteps(for staffStep: Int) -> [Int] {
        guard staffStep < 0 || staffStep > 8 else { return [] }
        guard staffStep.isMultiple(of: 2) else { return [] }
        return [staffStep]
    }

    func noteValue(forDurationTicks durationTicks: Int) -> ScrollingStaffNoteValue {
        let q = MusicXMLTempoMap.ticksPerQuarter
        if durationTicks >= q * 4 { return .whole }
        if durationTicks >= q * 2 { return .half }
        if durationTicks >= q { return .quarter }
        if durationTicks >= q / 2 { return .eighth }
        if durationTicks >= q / 4 { return .sixteenth }
        return .thirtySecond
    }

    private func makeChordLayout(items: [ScrollingStaffNotationItem])
        -> (items: [ScrollingStaffNotationItem], chords: [ScrollingStaffNotationChord])
    {
        let groups = Dictionary(grouping: items) { item in
            "\(item.guideID)-\(item.tick)-\(item.staff ?? 1)-\(item.voice ?? 1)"
        }

        var chordByItemID: [String: ScrollingStaffNotationChord] = [:]
        var offsetByItemID: [String: Double] = [:]
        var directionByItemID: [String: ScrollingStaffStemDirection] = [:]
        var chords: [ScrollingStaffNotationChord] = []
        chords.reserveCapacity(groups.count)

        for key in groups.keys.sorted() {
            guard let group = groups[key]?.sorted(by: chordSort) else { continue }
            let averageStep = Double(group.map(\.staffStep).reduce(0, +)) / Double(max(1, group.count))
            let middleStep = 4
            let farthestItem = group.max { abs($0.staffStep - middleStep) < abs($1.staffStep - middleStep) }
            let stemDirection: ScrollingStaffStemDirection = (farthestItem?.staffStep ?? Int(averageStep)) < middleStep ? .up : .down
            let chordID = "chord-\(key)"
            let chord = ScrollingStaffNotationChord(
                id: chordID,
                tick: group[0].tick,
                xPosition: group[0].xPosition,
                itemIDs: group.map(\.id),
                stemDirection: stemDirection,
                noteValue: shortestNoteValue(in: group)
            )
            chords.append(chord)

            for (index, item) in group.enumerated() {
                chordByItemID[item.id] = chord
                directionByItemID[item.id] = stemDirection
                offsetByItemID[item.id] = noteHeadOffset(
                    item: item,
                    index: index,
                    group: group,
                    stemDirection: stemDirection
                )
            }
        }

        let updatedItems = items.map { item in
            copyItem(
                item,
                chordID: chordByItemID[item.id]?.id,
                noteHeadXOffset: offsetByItemID[item.id] ?? 0,
                stemDirection: directionByItemID[item.id] ?? .up
            )
        }

        return (updatedItems, chords.sorted { lhs, rhs in
            if lhs.tick != rhs.tick { return lhs.tick < rhs.tick }
            return lhs.id < rhs.id
        })
    }

    private func makeBeamLayout(
        items: [ScrollingStaffNotationItem],
        chords: [ScrollingStaffNotationChord]
    ) -> (items: [ScrollingStaffNotationItem], chords: [ScrollingStaffNotationChord], beams: [ScrollingStaffNotationBeam]) {
        var beams: [ScrollingStaffNotationBeam] = []
        var currentGroup: [ScrollingStaffNotationChord] = []

        func flushCurrentGroup() {
            guard currentGroup.count >= 2 else {
                currentGroup.removeAll()
                return
            }
            let representativeValue = currentGroup.first?.noteValue ?? .eighth
            let beamCount: Int
            switch representativeValue {
                case .eighth: beamCount = 1
                case .sixteenth: beamCount = 2
                case .thirtySecond: beamCount = 3
                default: beamCount = 1
            }
            let beam = ScrollingStaffNotationBeam(
                id: "beam-\(beams.count + 1)-\(currentGroup.first?.tick ?? 0)",
                chordIDs: currentGroup.map(\.id),
                beamCount: beamCount
            )
            beams.append(beam)
            currentGroup.removeAll()
        }

        for chord in chords.sorted(by: { $0.tick < $1.tick }) {
            switch chord.noteValue {
                case .eighth, .sixteenth, .thirtySecond:
                    break
                default:
                    flushCurrentGroup()
                    continue
            }

            if let previous = currentGroup.last,
               chord.tick - previous.tick <= MusicXMLTempoMap.ticksPerQuarter,
               chord.stemDirection == previous.stemDirection
            {
                currentGroup.append(chord)
            } else {
                flushCurrentGroup()
                currentGroup = [chord]
            }
        }
        flushCurrentGroup()

        let beamIDByChordID = Dictionary(
            uniqueKeysWithValues: beams.flatMap { beam in
                beam.chordIDs.map { ($0, beam.id) }
            }
        )
        let updatedItems = items.map { item in
            copyItem(item, beamID: item.chordID.flatMap { beamIDByChordID[$0] })
        }

        return (updatedItems, chords, beams)
    }

    private func makeTieLayout(items: [ScrollingStaffNotationItem]) -> [ScrollingStaffNotationItem] {
        items.map { item in
            guard item.tieStart else { return item }
            let end = items.first { candidate in
                candidate.tick > item.tick &&
                    candidate.tieStop &&
                    candidate.midiNote == item.midiNote &&
                    (candidate.staff ?? 1) == (item.staff ?? 1) &&
                    (candidate.voice ?? 1) == (item.voice ?? 1)
            }
            return copyItem(item, tieEndXPosition: end?.xPosition)
        }
    }

    private func makeRests(
        guides: [PianoHighlightGuide],
        currentTick: Int,
        currentGuideID: Int?,
        safeHalfWindowTicks: Int
    ) -> [ScrollingStaffNotationRest] {
        guides.compactMap { guide -> ScrollingStaffNotationRest? in
            guard guide.isRestOrGap else { return nil }
            let xPosition = 0.5 + Double(guide.tick - currentTick) / Double(safeHalfWindowTicks * 2)
            guard xPosition >= -visibleOverscan, xPosition <= 1 + visibleOverscan else { return nil }
            return ScrollingStaffNotationRest(
                id: "rest-\(guide.id)-\(guide.tick)",
                guideID: guide.id,
                tick: guide.tick,
                xPosition: xPosition,
                noteValue: noteValue(forDurationTicks: max(1, guide.durationTicks ?? MusicXMLTempoMap.ticksPerQuarter)),
                isHighlighted: guide.id == currentGuideID
            )
        }
        .sorted { lhs, rhs in
            if lhs.tick != rhs.tick { return lhs.tick < rhs.tick }
            return lhs.id < rhs.id
        }
    }

    private func makeBarlines(
        measureSpans: [MusicXMLMeasureSpan],
        currentTick: Int,
        safeHalfWindowTicks: Int
    ) -> [ScrollingStaffNotationBarline] {
        var ticks = Set(measureSpans.map(\.startTick))
        if let lastEnd = measureSpans.map(\.endTick).max() {
            ticks.insert(lastEnd)
        }

        return ticks.sorted().compactMap { tick in
            let xPosition = 0.5 + Double(tick - currentTick) / Double(safeHalfWindowTicks * 2)
            guard xPosition >= -visibleOverscan, xPosition <= 1 + visibleOverscan else { return nil }
            return ScrollingStaffNotationBarline(id: "barline-\(tick)", tick: tick, xPosition: xPosition)
        }
    }

    private func shortestNoteValue(in items: [ScrollingStaffNotationItem]) -> ScrollingStaffNoteValue {
        items.map(\.noteValue).min { lhs, rhs in
            noteValueRank(lhs) < noteValueRank(rhs)
        } ?? .quarter
    }

    private func noteValueRank(_ value: ScrollingStaffNoteValue) -> Int {
        switch value {
            case .thirtySecond: 0
            case .sixteenth: 1
            case .eighth: 2
            case .quarter: 3
            case .half: 4
            case .whole: 5
        }
    }

    private func noteHeadOffset(
        item: ScrollingStaffNotationItem,
        index: Int,
        group: [ScrollingStaffNotationItem],
        stemDirection: ScrollingStaffStemDirection
    ) -> Double {
        let hasAdjacent = group.contains { other in
            other.id != item.id && abs(other.staffStep - item.staffStep) == 1
        }
        guard hasAdjacent, index % 2 == 1 else { return 0 }
        return stemDirection == .up ? -0.58 : 0.58
    }

    private func chordSort(lhs: ScrollingStaffNotationItem, rhs: ScrollingStaffNotationItem) -> Bool {
        if lhs.staffStep != rhs.staffStep { return lhs.staffStep < rhs.staffStep }
        return lhs.id < rhs.id
    }

    private func copyItem(
        _ item: ScrollingStaffNotationItem,
        chordID: String? = nil,
        noteHeadXOffset: Double? = nil,
        stemDirection: ScrollingStaffStemDirection? = nil,
        beamID: String? = nil,
        tieEndXPosition: Double? = nil
    ) -> ScrollingStaffNotationItem {
        ScrollingStaffNotationItem(
            occurrenceID: item.occurrenceID,
            midiNote: item.midiNote,
            guideID: item.guideID,
            tick: item.tick,
            xPosition: item.xPosition,
            staff: item.staff,
            voice: item.voice,
            staffStep: item.staffStep,
            showsSharpAccidental: item.showsSharpAccidental,
            isHighlighted: item.isHighlighted,
            fingeringText: item.fingeringText,
            noteValue: item.noteValue,
            chordID: chordID ?? item.chordID,
            noteHeadXOffset: noteHeadXOffset ?? item.noteHeadXOffset,
            stemDirection: stemDirection ?? item.stemDirection,
            beamID: beamID ?? item.beamID,
            durationTicks: item.durationTicks,
            isGrace: item.isGrace,
            tieStart: item.tieStart,
            tieStop: item.tieStop,
            tieEndXPosition: tieEndXPosition ?? item.tieEndXPosition,
            articulations: item.articulations,
            arpeggiate: item.arpeggiate,
            dotCount: item.dotCount
        )
    }

    private func diatonicIndex(for midiNote: Int) -> Int {
        let pitchClass = normalizedPitchClass(for: midiNote)
        let octave = (midiNote / 12) - 1
        return octave * 7 + (diatonicIndexByPitchClass[pitchClass] ?? 0)
    }

    private func normalizedPitchClass(for midiNote: Int) -> Int {
        ((midiNote % 12) + 12) % 12
    }
}
