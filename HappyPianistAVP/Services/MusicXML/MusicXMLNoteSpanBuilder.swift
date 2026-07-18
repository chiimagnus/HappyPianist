import Foundation

struct MusicXMLNoteSpanBuilder {
    private struct Key: Hashable {
        let partID: String
        let midiNote: Int
        let staff: Int
        let voice: Int
    }

    private enum Category {
        case start
        case middle
        case end
        case normal
    }

    func buildSpans(
        from notes: [MusicXMLNoteEvent],
        performanceTimingEnabled: Bool = false,
        expressivity: MusicXMLExpressivityOptions = MusicXMLExpressivityOptions(),
        logicalInstruments: [MusicXMLLogicalInstrument] = [],
        interpretationProfile: MusicXMLInterpretationProfile = .generic
    ) -> [MusicXMLNoteSpan] {
        let timingSchedule = ScoreTimingScheduleBuilder().build(
            notes: notes,
            performanceTimingEnabled: performanceTimingEnabled,
            graceEnabled: expressivity.graceEnabled,
            logicalInstruments: logicalInstruments,
            arpeggiateEnabled: expressivity.arpeggiateEnabled,
            interpretationProfile: interpretationProfile
        )
        let orderedNoteIndices = notes.indices.sorted { lhsIndex, rhsIndex in
            let lhsTiming = timingSchedule[lhsIndex]
            let rhsTiming = timingSchedule[rhsIndex]
            if lhsTiming.performedOnTick != rhsTiming.performedOnTick {
                return lhsTiming.performedOnTick < rhsTiming.performedOnTick
            }
            let lhs = notes[lhsIndex]
            let rhs = notes[rhsIndex]
            if lhs.tick != rhs.tick { return lhs.tick < rhs.tick }
            return (lhs.midiNote ?? -1) < (rhs.midiNote ?? -1)
        }

        var output: [MusicXMLNoteSpan] = []
        output.reserveCapacity(orderedNoteIndices.count)
        var activeSpanIndexByKey: [Key: Int] = [:]

        for noteIndex in orderedNoteIndices {
            let note = notes[noteIndex]
            let timing = timingSchedule[noteIndex]
            guard note.isRest == false else { continue }
            if note.isGrace, expressivity.graceEnabled == false { continue }
            guard let midiNote = note.midiNote else { continue }

            let staff = note.staff ?? 1
            let voice = note.voice ?? 1
            let key = Key(partID: note.partID, midiNote: midiNote, staff: staff, voice: voice)
            let category: Category = if note.tieStart, note.tieStop {
                .middle
            } else if note.tieStart {
                .start
            } else if note.tieStop {
                .end
            } else {
                .normal
            }
            let interval = MusicXMLNoteSpan(
                midiNote: midiNote,
                staff: staff,
                voice: voice,
                onTick: timing.performedOnTick,
                offTick: max(timing.performedOnTick, timing.performedOffTick)
            )

            switch category {
            case .start:
                output.append(interval)
                activeSpanIndexByKey[key] = output.count - 1
            case .middle:
                if let existingIndex = activeSpanIndexByKey[key] {
                    let existing = output[existingIndex]
                    output[existingIndex] = MusicXMLNoteSpan(
                        midiNote: existing.midiNote,
                        staff: existing.staff,
                        voice: existing.voice,
                        onTick: existing.onTick,
                        offTick: max(existing.offTick, interval.offTick)
                    )
                } else {
                    output.append(interval)
                    activeSpanIndexByKey[key] = output.count - 1
                }
            case .end:
                if let existingIndex = activeSpanIndexByKey[key] {
                    let existing = output[existingIndex]
                    output[existingIndex] = MusicXMLNoteSpan(
                        midiNote: existing.midiNote,
                        staff: existing.staff,
                        voice: existing.voice,
                        onTick: existing.onTick,
                        offTick: max(existing.offTick, interval.offTick)
                    )
                    activeSpanIndexByKey[key] = nil
                } else {
                    output.append(interval)
                }
            case .normal:
                output.append(interval)
            }
        }

        return output.sorted { lhs, rhs in
            if lhs.onTick != rhs.onTick { return lhs.onTick < rhs.onTick }
            if lhs.midiNote != rhs.midiNote { return lhs.midiNote < rhs.midiNote }
            return lhs.offTick < rhs.offTick
        }
    }
}
