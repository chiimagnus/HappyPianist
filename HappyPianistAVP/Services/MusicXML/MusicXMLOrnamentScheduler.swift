import Foundation

struct MusicXMLOrnamentScheduleResult: Equatable, Sendable {
    let generatedNotes: [ScoreGeneratedNoteEvent]
    let resolutions: [ScorePerformanceNotationResolution]
}

struct MusicXMLOrnamentScheduler {
    func schedule(
        notes: [MusicXMLNoteEvent],
        timingEntries: [ScoreTimingEntry],
        interpretationProfile: MusicXMLInterpretationProfile = .generic
    ) -> MusicXMLOrnamentScheduleResult {
        guard notes.count == timingEntries.count else {
            return MusicXMLOrnamentScheduleResult(generatedNotes: [], resolutions: [])
        }

        var generatedNotes: [ScoreGeneratedNoteEvent] = []
        var resolutions: [ScorePerformanceNotationResolution] = []

        for noteIndex in notes.indices {
            for notation in notes[noteIndex].performanceNotations {
                switch notation.kind {
                case .trillMark, .mordent, .invertedMordent, .turn, .invertedTurn:
                    let result = scheduleSingleNoteOrnament(
                        notation: notation,
                        noteIndex: noteIndex,
                        notes: notes,
                        timingEntries: timingEntries,
                        profile: interpretationProfile
                    )
                    generatedNotes.append(contentsOf: result.generatedNotes)
                    resolutions.append(result.resolution)
                case .tremolo:
                    let type = normalized(notation.typeToken) ?? "single"
                    if type == "single" || type == "unmeasured" {
                        let result = scheduleSingleNoteTremolo(
                            notation: notation,
                            noteIndex: noteIndex,
                            notes: notes,
                            timingEntries: timingEntries,
                            profile: interpretationProfile
                        )
                        generatedNotes.append(contentsOf: result.generatedNotes)
                        resolutions.append(result.resolution)
                    }
                default:
                    continue
                }
            }
        }

        let tremoloPairs = scheduleTwoNoteTremolos(
            notes: notes,
            timingEntries: timingEntries,
            profile: interpretationProfile
        )
        generatedNotes.append(contentsOf: tremoloPairs.generatedNotes)
        resolutions.append(contentsOf: tremoloPairs.resolutions)

        let glissandi = scheduleGlissandi(
            notes: notes,
            timingEntries: timingEntries,
            profile: interpretationProfile
        )
        generatedNotes.append(contentsOf: glissandi.generatedNotes)
        resolutions.append(contentsOf: glissandi.resolutions)

        return MusicXMLOrnamentScheduleResult(
            generatedNotes: generatedNotes.sorted(by: generatedNoteOrder),
            resolutions: resolutions.sorted(by: resolutionOrder)
        )
    }
}

private extension MusicXMLOrnamentScheduler {
    enum NeighborDirection {
        case upper
        case lower
    }

    struct Lane: Hashable {
        let partID: String
        let staff: Int
        let voice: Int
    }

    struct PairKey: Hashable {
        let lane: Lane
        let numberToken: String
    }

    struct PendingNotation {
        let noteIndex: Int
        let notation: MusicXMLPerformanceNotation
    }

    enum PitchResolution {
        case pitch(Int)
        case unsupported(String)
    }

    enum PitchSequenceResolution {
        case pitches([Int])
        case unsupported(String)
    }

    struct SingleResult {
        let generatedNotes: [ScoreGeneratedNoteEvent]
        let resolution: ScorePerformanceNotationResolution
    }

    struct BatchResult {
        let generatedNotes: [ScoreGeneratedNoteEvent]
        let resolutions: [ScorePerformanceNotationResolution]
    }

    func scheduleSingleNoteOrnament(
        notation: MusicXMLPerformanceNotation,
        noteIndex: Int,
        notes: [MusicXMLNoteEvent],
        timingEntries: [ScoreTimingEntry],
        profile: MusicXMLInterpretationProfile
    ) -> SingleResult {
        let note = notes[noteIndex]
        let entry = timingEntries[noteIndex]
        guard let mainPitch = note.midiNote else {
            return unsupported(
                notation: notation,
                noteIndices: [noteIndex],
                reason: "ornament-source-pitch-unavailable",
                profile: profile
            )
        }

        let pitchesResult: PitchSequenceResolution
        switch notation.kind {
        case .trillMark:
            switch auxiliaryPitch(for: note, direction: .upper, requiresPlacement: false) {
            case let .pitch(upper):
                let duration = entry.performedOffTick - entry.performedOnTick
                let subdivision = max(1, profile.ornamentSubdivisionTicks)
                var count = max(3, duration / subdivision)
                if count.isMultiple(of: 2) {
                    count += 1
                }
                count = min(max(3, count), max(3, duration))
                pitchesResult = .pitches((0..<count).map { $0.isMultiple(of: 2) ? mainPitch : upper })
            case let .unsupported(reason):
                pitchesResult = .unsupported(reason)
            }
        case .mordent:
            pitchesResult = ornamentSequence(
                mainPitch: mainPitch,
                neighbor: auxiliaryPitch(for: note, direction: .lower, requiresPlacement: false),
                inverted: false
            )
        case .invertedMordent:
            pitchesResult = ornamentSequence(
                mainPitch: mainPitch,
                neighbor: auxiliaryPitch(for: note, direction: .upper, requiresPlacement: false),
                inverted: false
            )
        case .turn, .invertedTurn:
            let upper = auxiliaryPitch(for: note, direction: .upper, requiresPlacement: true)
            let lower = auxiliaryPitch(for: note, direction: .lower, requiresPlacement: true)
            switch (upper, lower) {
            case let (.pitch(upperPitch), .pitch(lowerPitch)):
                pitchesResult = .pitches(
                    notation.kind == .invertedTurn
                        ? [lowerPitch, mainPitch, upperPitch, mainPitch]
                        : [upperPitch, mainPitch, lowerPitch, mainPitch]
                )
            case let (.unsupported(reason), _), let (_, .unsupported(reason)):
                pitchesResult = .unsupported(reason)
            }
        default:
            pitchesResult = .unsupported("unsupported-ornament-kind")
        }

        switch pitchesResult {
        case let .unsupported(reason):
            return unsupported(
                notation: notation,
                noteIndices: [noteIndex],
                reason: reason,
                profile: profile
            )
        case let .pitches(pitches):
            guard entry.performedOffTick - entry.performedOnTick >= pitches.count else {
                return unsupported(
                    notation: notation,
                    noteIndices: [noteIndex],
                    reason: "ornament-insufficient-duration",
                    profile: profile
                )
            }
            let events = generatedEvents(
                pitches: pitches,
                sourceNoteIndices: [noteIndex],
                notation: notation,
                purpose: .ornament,
                onTick: entry.performedOnTick,
                offTick: entry.performedOffTick,
                profile: profile
            )
            return SingleResult(
                generatedNotes: events,
                resolution: generatedResolution(
                    notation: notation,
                    noteIndices: [noteIndex],
                    replaces: [noteIndex],
                    profile: profile
                )
            )
        }
    }

    func scheduleSingleNoteTremolo(
        notation: MusicXMLPerformanceNotation,
        noteIndex: Int,
        notes: [MusicXMLNoteEvent],
        timingEntries: [ScoreTimingEntry],
        profile: MusicXMLInterpretationProfile
    ) -> SingleResult {
        guard let pitch = notes[noteIndex].midiNote else {
            return unsupported(
                notation: notation,
                noteIndices: [noteIndex],
                reason: "tremolo-source-pitch-unavailable",
                profile: profile
            )
        }
        let entry = timingEntries[noteIndex]
        let duration = entry.performedOffTick - entry.performedOnTick
        let type = normalized(notation.typeToken) ?? "single"
        let subdivision: Int
        if type == "unmeasured" {
            subdivision = max(1, profile.unmeasuredTremoloSubdivisionTicks)
        } else {
            guard let marks = tremoloMarks(notation), (1...8).contains(marks) else {
                return unsupported(
                    notation: notation,
                    noteIndices: [noteIndex],
                    reason: "measured-tremolo-marks-missing-or-invalid",
                    profile: profile
                )
            }
            subdivision = max(1, MusicXMLTempoMap.ticksPerQuarter / (1 << marks))
        }
        let count = max(2, duration / subdivision)
        guard duration >= count else {
            return unsupported(
                notation: notation,
                noteIndices: [noteIndex],
                reason: "tremolo-insufficient-duration",
                profile: profile
            )
        }
        let events = generatedEvents(
            pitches: Array(repeating: pitch, count: count),
            sourceNoteIndices: [noteIndex],
            notation: notation,
            purpose: .tremolo,
            onTick: entry.performedOnTick,
            offTick: entry.performedOffTick,
            profile: profile
        )
        return SingleResult(
            generatedNotes: events,
            resolution: generatedResolution(
                notation: notation,
                noteIndices: [noteIndex],
                replaces: [noteIndex],
                profile: profile
            )
        )
    }

    func scheduleTwoNoteTremolos(
        notes: [MusicXMLNoteEvent],
        timingEntries: [ScoreTimingEntry],
        profile: MusicXMLInterpretationProfile
    ) -> BatchResult {
        var activeByLane: [Lane: PendingNotation] = [:]
        var generatedNotes: [ScoreGeneratedNoteEvent] = []
        var resolutions: [ScorePerformanceNotationResolution] = []

        let ordered = notes.indices.sorted { lhs, rhs in
            if timingEntries[lhs].performedOnTick != timingEntries[rhs].performedOnTick {
                return timingEntries[lhs].performedOnTick < timingEntries[rhs].performedOnTick
            }
            return lhs < rhs
        }
        for noteIndex in ordered {
            for notation in notes[noteIndex].performanceNotations where notation.kind == .tremolo {
                let type = normalized(notation.typeToken) ?? "single"
                let lane = lane(for: notes[noteIndex])
                switch type {
                case "start":
                    if let previous = activeByLane.updateValue(
                        PendingNotation(noteIndex: noteIndex, notation: notation),
                        forKey: lane
                    ) {
                        resolutions.append(unsupportedResolution(
                            notation: previous.notation,
                            noteIndices: [previous.noteIndex],
                            reason: "tremolo-start-replaced-before-stop",
                            profile: profile
                        ))
                    }
                case "stop":
                    guard let start = activeByLane.removeValue(forKey: lane) else {
                        resolutions.append(unsupportedResolution(
                            notation: notation,
                            noteIndices: [noteIndex],
                            reason: "tremolo-stop-without-start",
                            profile: profile
                        ))
                        continue
                    }
                    let pair = scheduleTwoNoteTremoloPair(
                        start: start,
                        stop: PendingNotation(noteIndex: noteIndex, notation: notation),
                        notes: notes,
                        timingEntries: timingEntries,
                        profile: profile
                    )
                    generatedNotes.append(contentsOf: pair.generatedNotes)
                    resolutions.append(contentsOf: pair.resolutions)
                default:
                    continue
                }
            }
        }

        for pending in activeByLane.values {
            resolutions.append(unsupportedResolution(
                notation: pending.notation,
                noteIndices: [pending.noteIndex],
                reason: "tremolo-start-without-stop",
                profile: profile
            ))
        }
        return BatchResult(generatedNotes: generatedNotes, resolutions: resolutions)
    }

    func scheduleTwoNoteTremoloPair(
        start: PendingNotation,
        stop: PendingNotation,
        notes: [MusicXMLNoteEvent],
        timingEntries: [ScoreTimingEntry],
        profile: MusicXMLInterpretationProfile
    ) -> BatchResult {
        let indices = [start.noteIndex, stop.noteIndex].sorted()
        guard let firstPitch = notes[start.noteIndex].midiNote,
              let secondPitch = notes[stop.noteIndex].midiNote
        else {
            return unsupportedPair(
                start: start,
                stop: stop,
                reason: "two-note-tremolo-pitch-unavailable",
                profile: profile
            )
        }
        guard let marks = tremoloMarks(start.notation) ?? tremoloMarks(stop.notation),
              (1...8).contains(marks)
        else {
            return unsupportedPair(
                start: start,
                stop: stop,
                reason: "two-note-tremolo-marks-missing-or-invalid",
                profile: profile
            )
        }
        let onTick = min(
            timingEntries[start.noteIndex].performedOnTick,
            timingEntries[stop.noteIndex].performedOnTick
        )
        let offTick = max(
            timingEntries[start.noteIndex].performedOffTick,
            timingEntries[stop.noteIndex].performedOffTick
        )
        let duration = offTick - onTick
        let subdivision = max(1, MusicXMLTempoMap.ticksPerQuarter / (1 << marks))
        var count = max(2, duration / subdivision)
        if count.isMultiple(of: 2) == false {
            count += 1
        }
        guard duration >= count else {
            return unsupportedPair(
                start: start,
                stop: stop,
                reason: "two-note-tremolo-insufficient-duration",
                profile: profile
            )
        }
        let pitches = (0..<count).map { $0.isMultiple(of: 2) ? firstPitch : secondPitch }
        let events = generatedEvents(
            pitches: pitches,
            sourceNoteIndices: indices,
            notation: start.notation,
            purpose: .tremolo,
            onTick: onTick,
            offTick: offTick,
            profile: profile
        )
        let resolutions = [start.notation, stop.notation].map {
            generatedResolution(
                notation: $0,
                noteIndices: indices,
                replaces: indices,
                profile: profile
            )
        }
        return BatchResult(generatedNotes: events, resolutions: resolutions)
    }

    func scheduleGlissandi(
        notes: [MusicXMLNoteEvent],
        timingEntries: [ScoreTimingEntry],
        profile: MusicXMLInterpretationProfile
    ) -> BatchResult {
        var activeByKey: [PairKey: PendingNotation] = [:]
        var generatedNotes: [ScoreGeneratedNoteEvent] = []
        var resolutions: [ScorePerformanceNotationResolution] = []

        let ordered = notes.indices.sorted { lhs, rhs in
            if timingEntries[lhs].performedOnTick != timingEntries[rhs].performedOnTick {
                return timingEntries[lhs].performedOnTick < timingEntries[rhs].performedOnTick
            }
            return lhs < rhs
        }
        for noteIndex in ordered {
            for notation in notes[noteIndex].performanceNotations where notation.kind == .glissando {
                let key = PairKey(
                    lane: lane(for: notes[noteIndex]),
                    numberToken: normalized(notation.numberToken) ?? "1"
                )
                switch normalized(notation.typeToken) {
                case "start":
                    if let previous = activeByKey.updateValue(
                        PendingNotation(noteIndex: noteIndex, notation: notation),
                        forKey: key
                    ) {
                        resolutions.append(unsupportedResolution(
                            notation: previous.notation,
                            noteIndices: [previous.noteIndex],
                            reason: "glissando-start-replaced-before-stop",
                            profile: profile
                        ))
                    }
                case "stop":
                    guard let start = activeByKey.removeValue(forKey: key) else {
                        resolutions.append(unsupportedResolution(
                            notation: notation,
                            noteIndices: [noteIndex],
                            reason: "glissando-stop-without-start",
                            profile: profile
                        ))
                        continue
                    }
                    let pair = scheduleGlissandoPair(
                        start: start,
                        stop: PendingNotation(noteIndex: noteIndex, notation: notation),
                        notes: notes,
                        timingEntries: timingEntries,
                        profile: profile
                    )
                    generatedNotes.append(contentsOf: pair.generatedNotes)
                    resolutions.append(contentsOf: pair.resolutions)
                default:
                    resolutions.append(unsupportedResolution(
                        notation: notation,
                        noteIndices: [noteIndex],
                        reason: "glissando-missing-or-unsupported-type",
                        profile: profile
                    ))
                }
            }
        }

        for pending in activeByKey.values {
            resolutions.append(unsupportedResolution(
                notation: pending.notation,
                noteIndices: [pending.noteIndex],
                reason: "glissando-start-without-stop",
                profile: profile
            ))
        }
        return BatchResult(generatedNotes: generatedNotes, resolutions: resolutions)
    }

    func scheduleGlissandoPair(
        start: PendingNotation,
        stop: PendingNotation,
        notes: [MusicXMLNoteEvent],
        timingEntries: [ScoreTimingEntry],
        profile: MusicXMLInterpretationProfile
    ) -> BatchResult {
        let indices = [start.noteIndex, stop.noteIndex].sorted()
        guard let startPitch = notes[start.noteIndex].midiNote,
              let stopPitch = notes[stop.noteIndex].midiNote
        else {
            return unsupportedPair(
                start: start,
                stop: stop,
                reason: "glissando-endpoint-pitch-unavailable",
                profile: profile
            )
        }
        guard startPitch != stopPitch else {
            return unsupportedPair(
                start: start,
                stop: stop,
                reason: "glissando-identical-endpoints",
                profile: profile
            )
        }
        guard profile.glissandoPitchPolicy == .chromatic else {
            return unsupportedPair(
                start: start,
                stop: stop,
                reason: "glissando-scale-policy-unavailable",
                profile: profile
            )
        }
        let onTick = timingEntries[start.noteIndex].performedOnTick
        let offTick = timingEntries[stop.noteIndex].performedOnTick
        guard offTick > onTick else {
            return unsupportedPair(
                start: start,
                stop: stop,
                reason: "glissando-endpoint-order-invalid",
                profile: profile
            )
        }
        let step = stopPitch > startPitch ? 1 : -1
        let pitches = Array(stride(from: startPitch, to: stopPitch, by: step))
        guard pitches.isEmpty == false, offTick - onTick >= pitches.count else {
            return unsupportedPair(
                start: start,
                stop: stop,
                reason: "glissando-insufficient-duration",
                profile: profile
            )
        }
        let events = generatedEvents(
            pitches: pitches,
            sourceNoteIndices: indices,
            notation: start.notation,
            purpose: .glissando,
            onTick: onTick,
            offTick: offTick,
            profile: profile
        )
        let resolutions = [
            generatedResolution(
                notation: start.notation,
                noteIndices: indices,
                replaces: [start.noteIndex],
                profile: profile
            ),
            generatedResolution(
                notation: stop.notation,
                noteIndices: indices,
                replaces: [],
                profile: profile
            ),
        ]
        return BatchResult(generatedNotes: events, resolutions: resolutions)
    }

    func ornamentSequence(
        mainPitch: Int,
        neighbor: PitchResolution,
        inverted _: Bool
    ) -> PitchSequenceResolution {
        switch neighbor {
        case let .pitch(neighborPitch):
            return .pitches([mainPitch, neighborPitch, mainPitch])
        case let .unsupported(reason):
            return .unsupported(reason)
        }
    }

    func auxiliaryPitch(
        for note: MusicXMLNoteEvent,
        direction: NeighborDirection,
        requiresPlacement: Bool
    ) -> PitchResolution {
        guard let writtenPitch = note.writtenPitch else {
            return .unsupported("ornament-written-pitch-unavailable")
        }
        let accidentalMarks = note.performanceNotations.filter { $0.kind == .accidentalMark }
        let expectedPlacement = direction == .upper ? "above" : "below"
        let selected: MusicXMLPerformanceNotation?
        if let placed = accidentalMarks.first(where: {
            normalized($0.placementToken) == expectedPlacement
        }) {
            selected = placed
        } else if requiresPlacement == false, accidentalMarks.count == 1 {
            selected = accidentalMarks[0]
        } else {
            selected = nil
        }
        guard let selected else {
            return .unsupported("ornament-accidental-unavailable")
        }
        guard let alter = accidentalAlter(selected.textToken) else {
            return .unsupported("ornament-accidental-unsupported")
        }
        guard let neighbor = neighboringPitch(writtenPitch, direction: direction, alter: alter) else {
            return .unsupported("ornament-auxiliary-pitch-out-of-range")
        }
        return .pitch(neighbor)
    }

    func neighboringPitch(
        _ source: MusicXMLWrittenPitch,
        direction: NeighborDirection,
        alter: Int
    ) -> Int? {
        let steps = ["C", "D", "E", "F", "G", "A", "B"]
        guard let sourceIndex = steps.firstIndex(of: source.step.uppercased()) else { return nil }
        let targetIndex: Int
        let octave: Int
        switch direction {
        case .upper:
            targetIndex = (sourceIndex + 1) % steps.count
            octave = source.octave + (sourceIndex == steps.count - 1 ? 1 : 0)
        case .lower:
            targetIndex = (sourceIndex - 1 + steps.count) % steps.count
            octave = source.octave - (sourceIndex == 0 ? 1 : 0)
        }
        let semitoneByStep = [0, 2, 4, 5, 7, 9, 11]
        let midi = (octave + 1) * 12 + semitoneByStep[targetIndex] + alter
        return (0...127).contains(midi) ? midi : nil
    }

    func accidentalAlter(_ token: String?) -> Int? {
        switch normalized(token) {
        case "natural": 0
        case "sharp": 1
        case "flat": -1
        case "double-sharp", "sharp-sharp": 2
        case "double-flat", "flat-flat": -2
        default: nil
        }
    }

    func tremoloMarks(_ notation: MusicXMLPerformanceNotation) -> Int? {
        guard let token = normalized(notation.textToken), let marks = Int(token) else { return nil }
        return marks
    }

    func generatedEvents(
        pitches: [Int],
        sourceNoteIndices: [Int],
        notation: MusicXMLPerformanceNotation,
        purpose: ScoreGeneratedNotePurpose,
        onTick: Int,
        offTick: Int,
        profile: MusicXMLInterpretationProfile
    ) -> [ScoreGeneratedNoteEvent] {
        let intervals = partition(onTick: onTick, offTick: offTick, count: pitches.count)
        return zip(pitches, intervals).enumerated().map { ordinal, pair in
            ScoreGeneratedNoteEvent(
                sourceNoteIndices: sourceNoteIndices.sorted(),
                sourceNotationID: notation.sourceID,
                notationKind: notation.kind,
                purpose: purpose,
                ordinal: ordinal,
                midiNote: pair.0,
                onTick: pair.1.onTick,
                offTick: pair.1.offTick,
                interpretationProfileID: profile.id
            )
        }
    }

    func partition(onTick: Int, offTick: Int, count: Int) -> [(onTick: Int, offTick: Int)] {
        guard count > 0, offTick > onTick else { return [] }
        let duration = offTick - onTick
        let base = duration / count
        let remainder = duration % count
        var cursor = onTick
        return (0..<count).map { index in
            let length = base + (index < remainder ? 1 : 0)
            let interval = (onTick: cursor, offTick: cursor + length)
            cursor += length
            return interval
        }
    }

    func generatedResolution(
        notation: MusicXMLPerformanceNotation,
        noteIndices: [Int],
        replaces: [Int],
        profile: MusicXMLInterpretationProfile
    ) -> ScorePerformanceNotationResolution {
        ScorePerformanceNotationResolution(
            sourceNotationID: notation.sourceID,
            notationKind: notation.kind,
            sourceNoteIndices: noteIndices.sorted(),
            replacesSourceNoteIndices: replaces.sorted(),
            status: .generated,
            interpretationProfileID: profile.id
        )
    }

    func unsupported(
        notation: MusicXMLPerformanceNotation,
        noteIndices: [Int],
        reason: String,
        profile: MusicXMLInterpretationProfile
    ) -> SingleResult {
        SingleResult(
            generatedNotes: [],
            resolution: unsupportedResolution(
                notation: notation,
                noteIndices: noteIndices,
                reason: reason,
                profile: profile
            )
        )
    }

    func unsupportedPair(
        start: PendingNotation,
        stop: PendingNotation,
        reason: String,
        profile: MusicXMLInterpretationProfile
    ) -> BatchResult {
        let indices = [start.noteIndex, stop.noteIndex].sorted()
        return BatchResult(
            generatedNotes: [],
            resolutions: [start.notation, stop.notation].map {
                unsupportedResolution(
                    notation: $0,
                    noteIndices: indices,
                    reason: reason,
                    profile: profile
                )
            }
        )
    }

    func unsupportedResolution(
        notation: MusicXMLPerformanceNotation,
        noteIndices: [Int],
        reason: String,
        profile: MusicXMLInterpretationProfile
    ) -> ScorePerformanceNotationResolution {
        ScorePerformanceNotationResolution(
            sourceNotationID: notation.sourceID,
            notationKind: notation.kind,
            sourceNoteIndices: noteIndices.sorted(),
            replacesSourceNoteIndices: [],
            status: .unsupported(reason: reason),
            interpretationProfileID: profile.id
        )
    }

    func lane(for note: MusicXMLNoteEvent) -> Lane {
        Lane(partID: note.partID, staff: note.staff ?? 1, voice: note.voice ?? 1)
    }

    func normalized(_ token: String?) -> String? {
        let value = token?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return value.isEmpty ? nil : value
    }

    func generatedNoteOrder(_ lhs: ScoreGeneratedNoteEvent, _ rhs: ScoreGeneratedNoteEvent) -> Bool {
        if lhs.onTick != rhs.onTick { return lhs.onTick < rhs.onTick }
        if lhs.midiNote != rhs.midiNote { return lhs.midiNote < rhs.midiNote }
        if lhs.purpose.rawValue != rhs.purpose.rawValue { return lhs.purpose.rawValue < rhs.purpose.rawValue }
        return lhs.ordinal < rhs.ordinal
    }

    func resolutionOrder(
        _ lhs: ScorePerformanceNotationResolution,
        _ rhs: ScorePerformanceNotationResolution
    ) -> Bool {
        let lhsIndex = lhs.sourceNoteIndices.first ?? Int.max
        let rhsIndex = rhs.sourceNoteIndices.first ?? Int.max
        if lhsIndex != rhsIndex { return lhsIndex < rhsIndex }
        if lhs.notationKind.rawValue != rhs.notationKind.rawValue {
            return lhs.notationKind.rawValue < rhs.notationKind.rawValue
        }
        return (lhs.sourceNotationID?.sourceOrdinal ?? Int.max) < (rhs.sourceNotationID?.sourceOrdinal ?? Int.max)
    }
}
