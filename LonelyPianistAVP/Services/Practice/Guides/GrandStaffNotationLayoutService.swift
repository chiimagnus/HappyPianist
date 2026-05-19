import Foundation

protocol GrandStaffNotationLayoutServiceProtocol {
    func makeLayout(
        guides: [PianoHighlightGuide],
        currentGuide: PianoHighlightGuide?,
        measureSpans: [MusicXMLMeasureSpan],
        context: GrandStaffNotationContext?,
        halfWindowTicks: Int,
        scrollTick: Double?
    ) -> GrandStaffNotationLayout

    func staffStep(for midiNote: Int, staffNumber: Int) -> Int
    func ledgerStaffSteps(for staffStep: Int) -> [Int]
}

struct GrandStaffNotationLayoutService: GrandStaffNotationLayoutServiceProtocol {
    private struct ChordKey: Hashable {
        let tick: Int
        let staffNumber: Int
        let voice: Int
    }

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
        halfWindowTicks: Int = 1920,
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
                let voice = note.voice ?? 1
                return GrandStaffNotationItem(
                    occurrenceID: note.occurrenceID,
                    staffNumber: staffNumber,
                    voice: voice,
                    hand: note.hand,
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
            if lhs.voice != rhs.voice { return lhs.voice < rhs.voice }
            if lhs.midiNote != rhs.midiNote { return lhs.midiNote < rhs.midiNote }
            return lhs.occurrenceID < rhs.occurrenceID
        }

        let chordBuild = buildChordsAndBeams(items: rawItems, measureSpans: measureSpans)

        let barlines = makeBarlines(
            measureSpans: measureSpans,
            currentTick: currentTick,
            safeHalfWindowTicks: safeHalfWindowTicks
        )

        return GrandStaffNotationLayout(
            items: chordBuild.items,
            chords: chordBuild.chords,
            rests: [],
            barlines: barlines,
            beams: chordBuild.beams,
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

    private func buildChordsAndBeams(
        items: [GrandStaffNotationItem],
        measureSpans: [MusicXMLMeasureSpan]
    ) -> (items: [GrandStaffNotationItem], chords: [GrandStaffNotationChord], beams: [GrandStaffNotationBeam]) {
        guard items.isEmpty == false else { return (items, [], []) }

        let barlineTicks = Set(measureSpans.map(\.startTick))
            .union([measureSpans.map(\.endTick).max()].compactMap(\.self))

        let grouped = Dictionary(
            grouping: items,
            by: { ChordKey(tick: $0.tick, staffNumber: $0.staffNumber, voice: $0.voice) }
        )
        let sortedKeys = grouped.keys.sorted { lhs, rhs in
            if lhs.tick != rhs.tick { return lhs.tick < rhs.tick }
            if lhs.staffNumber != rhs.staffNumber { return lhs.staffNumber < rhs.staffNumber }
            return lhs.voice < rhs.voice
        }

        var chords: [GrandStaffNotationChord] = []
        chords.reserveCapacity(sortedKeys.count)

        var updatedItemsByOccurrenceID: [String: GrandStaffNotationItem] = [:]
        updatedItemsByOccurrenceID.reserveCapacity(items.count)

        for key in sortedKeys {
            guard let chordItems = grouped[key], chordItems.isEmpty == false else { continue }

            let chordID = "chord-\(key.tick)-\(key.staffNumber)-\(key.voice)"
            let xPosition = chordItems.map(\.xPosition).reduce(0.0, +) / Double(chordItems.count)
            let stemDirection = resolvedStemDirection(chordItems: chordItems)
            let noteValue = resolvedChordNoteValue(items: chordItems)

            chords.append(GrandStaffNotationChord(
                id: chordID,
                tick: key.tick,
                xPosition: xPosition,
                itemIDs: chordItems.map(\.occurrenceID),
                stemDirection: stemDirection,
                noteValue: noteValue
            ))

            for item in chordItems {
                updatedItemsByOccurrenceID[item.occurrenceID] = GrandStaffNotationItem(
                    occurrenceID: item.occurrenceID,
                    staffNumber: item.staffNumber,
                    voice: item.voice,
                    hand: item.hand,
                    midiNote: item.midiNote,
                    guideID: item.guideID,
                    tick: item.tick,
                    xPosition: item.xPosition,
                    staffStep: item.staffStep,
                    showsSharpAccidental: item.showsSharpAccidental,
                    isHighlighted: item.isHighlighted,
                    fingeringText: item.fingeringText,
                    noteValue: item.noteValue,
                    chordID: chordID,
                    noteHeadXOffset: item.noteHeadXOffset,
                    stemDirection: stemDirection,
                    beamID: nil,
                    durationTicks: item.durationTicks,
                    isGrace: item.isGrace,
                    tieStart: item.tieStart,
                    tieStop: item.tieStop,
                    tieEndXPosition: item.tieEndXPosition,
                    articulations: item.articulations,
                    arpeggiate: item.arpeggiate,
                    dotCount: item.dotCount
                )
            }
        }

        _ = items.compactMap { updatedItemsByOccurrenceID[$0.occurrenceID] }

        let beamsBuild = buildBeams(
            chords: chords,
            barlineTicks: barlineTicks
        )

        var beamedItemsByOccurrenceID = updatedItemsByOccurrenceID
        for (beamID, chordIDs) in beamsBuild.beamChordIDsByBeamID {
            for chordID in chordIDs {
                guard let chord = chords.first(where: { $0.id == chordID }) else { continue }
                for itemID in chord.itemIDs {
                    if let existing = beamedItemsByOccurrenceID[itemID] {
                        beamedItemsByOccurrenceID[itemID] = GrandStaffNotationItem(
                            occurrenceID: existing.occurrenceID,
                            staffNumber: existing.staffNumber,
                            voice: existing.voice,
                            hand: existing.hand,
                            midiNote: existing.midiNote,
                            guideID: existing.guideID,
                            tick: existing.tick,
                            xPosition: existing.xPosition,
                            staffStep: existing.staffStep,
                            showsSharpAccidental: existing.showsSharpAccidental,
                            isHighlighted: existing.isHighlighted,
                            fingeringText: existing.fingeringText,
                            noteValue: existing.noteValue,
                            chordID: existing.chordID,
                            noteHeadXOffset: existing.noteHeadXOffset,
                            stemDirection: existing.stemDirection,
                            beamID: beamID,
                            durationTicks: existing.durationTicks,
                            isGrace: existing.isGrace,
                            tieStart: existing.tieStart,
                            tieStop: existing.tieStop,
                            tieEndXPosition: existing.tieEndXPosition,
                            articulations: existing.articulations,
                            arpeggiate: existing.arpeggiate,
                            dotCount: existing.dotCount
                        )
                    }
                }
            }
        }

        _ = items.compactMap { beamedItemsByOccurrenceID[$0.occurrenceID] }

        let finalChords = enforceBeamGroupStemDirections(
            chords: chords,
            itemsByOccurrenceID: beamedItemsByOccurrenceID,
            beamChordIDsByBeamID: beamsBuild.beamChordIDsByBeamID
        )
        var finalItemsByOccurrenceID = beamedItemsByOccurrenceID
        for chord in finalChords {
            for itemID in chord.itemIDs {
                if let existing = finalItemsByOccurrenceID[itemID] {
                    finalItemsByOccurrenceID[itemID] = GrandStaffNotationItem(
                        occurrenceID: existing.occurrenceID,
                        staffNumber: existing.staffNumber,
                        voice: existing.voice,
                        hand: existing.hand,
                        midiNote: existing.midiNote,
                        guideID: existing.guideID,
                        tick: existing.tick,
                        xPosition: existing.xPosition,
                        staffStep: existing.staffStep,
                        showsSharpAccidental: existing.showsSharpAccidental,
                        isHighlighted: existing.isHighlighted,
                        fingeringText: existing.fingeringText,
                        noteValue: existing.noteValue,
                        chordID: existing.chordID,
                        noteHeadXOffset: existing.noteHeadXOffset,
                        stemDirection: chord.stemDirection,
                        beamID: existing.beamID,
                        durationTicks: existing.durationTicks,
                        isGrace: existing.isGrace,
                        tieStart: existing.tieStart,
                        tieStop: existing.tieStop,
                        tieEndXPosition: existing.tieEndXPosition,
                        articulations: existing.articulations,
                        arpeggiate: existing.arpeggiate,
                        dotCount: existing.dotCount
                    )
                }
            }
        }

        let normalizedItems = items.compactMap { finalItemsByOccurrenceID[$0.occurrenceID] }

        return (normalizedItems, finalChords, beamsBuild.beams)
    }

    private func resolvedStemDirection(chordItems: [GrandStaffNotationItem]) -> GrandStaffStemDirection {
        if chordItems.contains(where: { $0.hand == .left }) {
            return .down
        }
        return .up
    }

    private func resolvedChordNoteValue(items: [GrandStaffNotationItem]) -> GrandStaffNoteValue {
        guard items.isEmpty == false else { return .quarter }
        return items.map(\.noteValue).min(by: { beamRank(for: $0) < beamRank(for: $1) }) ?? items[0].noteValue
    }

    private func beamRank(for noteValue: GrandStaffNoteValue) -> Int {
        switch noteValue {
            case .thirtySecond:
                0
            case .sixteenth:
                1
            case .eighth:
                2
            case .quarter:
                3
            case .half:
                4
            case .whole:
                5
        }
    }

    private func buildBeams(
        chords: [GrandStaffNotationChord],
        barlineTicks: Set<Int>
    ) -> (beams: [GrandStaffNotationBeam], beamChordIDsByBeamID: [String: [String]]) {
        if chords.isEmpty { return ([], [:]) }

        let eligible = chords
            .filter { $0.noteValue == .eighth || $0.noteValue == .sixteenth || $0.noteValue == .thirtySecond }
            .sorted { lhs, rhs in
                if lhs.tick != rhs.tick { return lhs.tick < rhs.tick }
                return lhs.id < rhs.id
            }

        var chordsByTrack: [String: [GrandStaffNotationChord]] = [:]
        for chord in eligible {
            let track = chordTrackKey(chordID: chord.id)
            chordsByTrack[track, default: []].append(chord)
        }

        var beams: [GrandStaffNotationBeam] = []
        var beamChordIDsByBeamID: [String: [String]] = [:]
        var beamCounter = 0

        for (_, trackChords) in chordsByTrack {
            var currentGroup: [GrandStaffNotationChord] = []
            var lastTick: Int?

            func flush() {
                guard currentGroup.count >= 2 else {
                    currentGroup.removeAll(keepingCapacity: true)
                    return
                }
                beamCounter += 1
                let beamID = "beam-\(beamCounter)"
                let chordIDs = currentGroup.map(\.id)
                beamChordIDsByBeamID[beamID] = chordIDs
                let maxBeamCount = currentGroup.map(\.noteValue).map(beamCount(for:)).max() ?? 1
                beams.append(GrandStaffNotationBeam(id: beamID, chordIDs: chordIDs, beamCount: max(1, maxBeamCount)))
                currentGroup.removeAll(keepingCapacity: true)
                lastTick = nil
            }

            for chord in trackChords.sorted(by: { $0.tick < $1.tick }) {
                if barlineTicks.contains(chord.tick), currentGroup.isEmpty == false {
                    flush()
                }

                if let lastTick {
                    let delta = chord.tick - lastTick
                    if delta > MusicXMLTempoMap.ticksPerQuarter {
                        flush()
                    }
                }

                currentGroup.append(chord)
                lastTick = chord.tick
            }
            flush()
        }

        return (beams, beamChordIDsByBeamID)
    }

    private func enforceBeamGroupStemDirections(
        chords: [GrandStaffNotationChord],
        itemsByOccurrenceID: [String: GrandStaffNotationItem],
        beamChordIDsByBeamID: [String: [String]]
    ) -> [GrandStaffNotationChord] {
        guard beamChordIDsByBeamID.isEmpty == false else { return chords }

        var overrideByChordID: [String: GrandStaffStemDirection] = [:]

        for chordIDs in beamChordIDsByBeamID.values {
            var hasLeftHand = false
            var hasRightHand = false

            for chordID in chordIDs {
                guard let chord = chords.first(where: { $0.id == chordID }) else { continue }
                for itemID in chord.itemIDs {
                    guard let item = itemsByOccurrenceID[itemID] else { continue }
                    if item.hand == .left { hasLeftHand = true } else { hasRightHand = true }
                }
            }

            let direction: GrandStaffStemDirection
            if hasLeftHand, hasRightHand == false {
                direction = .down
            } else if hasRightHand, hasLeftHand == false {
                direction = .up
            } else {
                // Mixed fallback: prefer staff number encoded in chordID (chord-<tick>-<staff>-<voice>)
                let staffToken = chordIDs.first?.split(separator: "-").dropFirst(2).first
                if let staffToken, let staff = Int(staffToken), staff >= 2 {
                    direction = .down
                } else {
                    direction = .up
                }
            }

            for chordID in chordIDs {
                overrideByChordID[chordID] = direction
            }
        }

        return chords.map { chord in
            if let forced = overrideByChordID[chord.id], forced != chord.stemDirection {
                return GrandStaffNotationChord(
                    id: chord.id,
                    tick: chord.tick,
                    xPosition: chord.xPosition,
                    itemIDs: chord.itemIDs,
                    stemDirection: forced,
                    noteValue: chord.noteValue
                )
            }
            return chord
        }
    }

    private func beamCount(for noteValue: GrandStaffNoteValue) -> Int {
        switch noteValue {
            case .eighth:
                1
            case .sixteenth:
                2
            case .thirtySecond:
                3
            default:
                0
        }
    }

    private func chordTrackKey(chordID: String) -> String {
        // chord-<tick>-<staff>-<voice>
        let parts = chordID.split(separator: "-")
        guard parts.count >= 4 else { return chordID }
        let staff = parts[2]
        let voice = parts[3]
        return "\(staff)-\(voice)"
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
