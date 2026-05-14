import Foundation

struct GrandStaffNotationLayoutService {
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

    func makeLayout(
        guides: [PianoHighlightGuide],
        currentGuide: PianoHighlightGuide?,
        measureSpans: [MusicXMLMeasureSpan] = [],
        context: GrandStaffNotationContext? = nil,
        halfWindowTicks: Int = 1_920,
        scrollTick: Double? = nil
    ) -> GrandStaffNotationLayout {
        guard guides.isEmpty == false else {
            return GrandStaffNotationLayout(
                items: [],
                chords: [],
                rests: [],
                barlines: [],
                beams: [],
                context: context
            )
        }

        let currentTick: Double = scrollTick ?? Double(currentGuide?.tick ?? guides.first?.tick ?? 0)
        let safeHalfWindowTicks = max(1, halfWindowTicks)
        let currentGuideID = currentGuide?.id

        let rawItems = guides.flatMap { guide in
            guide.triggeredNotes.map { note in
                let xPosition = 0.5 + (Double(guide.tick) - currentTick) / Double(safeHalfWindowTicks * 2)
                let staffNumber = resolvedStaffNumber(note.staff)
                return GrandStaffNotationItem(
                    occurrenceID: note.occurrenceID,
                    staffNumber: staffNumber,
                    midiNote: note.midiNote,
                    guideID: guide.id,
                    tick: guide.tick,
                    xPosition: xPosition,
                    staffStep: staffStep(for: note.midiNote, staffNumber: staffNumber),
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
            if lhs.staffNumber != rhs.staffNumber { return lhs.staffNumber < rhs.staffNumber }
            if lhs.midiNote != rhs.midiNote { return lhs.midiNote < rhs.midiNote }
            return lhs.occurrenceID < rhs.occurrenceID
        }

        let barlines = makeBarlines(
            measureSpans: measureSpans,
            currentTick: currentTick,
            safeHalfWindowTicks: safeHalfWindowTicks
        )

        return GrandStaffNotationLayout(
            items: rawItems,
            chords: [],
            rests: [],
            barlines: barlines,
            beams: [],
            context: context
        )
    }

    func staffStep(for midiNote: Int, staffNumber: Int) -> Int {
        let bottomLineMIDINote = (staffNumber >= 2) ? bassBottomLineMIDINote : trebleBottomLineMIDINote
        return diatonicIndex(for: midiNote) - diatonicIndex(for: bottomLineMIDINote)
    }

    func showsSharpAccidental(for midiNote: Int) -> Bool {
        blackKeyPitchClasses.contains(normalizedPitchClass(for: midiNote))
    }

    func ledgerStaffSteps(for staffStep: Int) -> [Int] {
        guard staffStep < 0 || staffStep > 8 else { return [] }

        var steps: [Int] = []
        if staffStep < 0 {
            var cursor = staffStep
            while cursor < 0 {
                if cursor % 2 == 0 { steps.append(cursor) }
                cursor += 1
            }
        } else {
            var cursor = staffStep
            while cursor > 8 {
                if cursor % 2 == 0 { steps.append(cursor) }
                cursor -= 1
            }
        }
        return steps
    }

    private func noteValue(forDurationTicks durationTicks: Int) -> GrandStaffNoteValue {
        let ticks = max(1, durationTicks)
        if ticks >= MusicXMLTempoMap.ticksPerQuarter * 4 { return .whole }
        if ticks >= MusicXMLTempoMap.ticksPerQuarter * 2 { return .half }
        if ticks >= MusicXMLTempoMap.ticksPerQuarter { return .quarter }
        if ticks >= MusicXMLTempoMap.ticksPerQuarter / 2 { return .eighth }
        if ticks >= MusicXMLTempoMap.ticksPerQuarter / 4 { return .sixteenth }
        return .thirtySecond
    }

    private func makeBarlines(
        measureSpans: [MusicXMLMeasureSpan],
        currentTick: Double,
        safeHalfWindowTicks: Int
    ) -> [GrandStaffNotationBarline] {
        var ticks = Set(measureSpans.map(\.startTick))
        if let lastEnd = measureSpans.map(\.endTick).max() {
            ticks.insert(lastEnd)
        }

        return ticks.sorted().compactMap { tick in
            let xPosition = 0.5 + (Double(tick) - currentTick) / Double(safeHalfWindowTicks * 2)
            guard xPosition >= -visibleOverscan, xPosition <= 1 + visibleOverscan else { return nil }
            return GrandStaffNotationBarline(id: "barline-\(tick)", tick: tick, xPosition: xPosition)
        }
    }

    private func resolvedStaffNumber(_ staff: Int?) -> Int {
        guard let staff else { return 1 }
        return (staff >= 2) ? 2 : 1
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
