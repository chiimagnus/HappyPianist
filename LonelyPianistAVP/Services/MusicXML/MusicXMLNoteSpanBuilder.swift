import Foundation

struct MusicXMLNoteSpanBuilder {
    private struct Key: Hashable {
        let partID: String
        let midiNote: Int
        let staff: Int
        let voice: Int
    }

    func buildSpans(from notes: [MusicXMLNoteEvent], performanceTimingEnabled: Bool = false) -> [MusicXMLNoteSpan] {
        let orderedNotes = notes.sorted { lhs, rhs in
            if lhs.tick != rhs.tick { return lhs.tick < rhs.tick }
            return (lhs.midiNote ?? -1) < (rhs.midiNote ?? -1)
        }

        var output: [MusicXMLNoteSpan] = []
        output.reserveCapacity(orderedNotes.count)

        var activeSpanIndexByKey: [Key: Int] = [:]

        for note in orderedNotes {
            guard note.isRest == false else { continue }
            guard note.isGrace == false else { continue }
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

            switch category {
                case .start:
                    if activeSpanIndexByKey[key] != nil {
                        #if DEBUG
                            print(
                                "MusicXMLNoteSpanBuilder: duplicate tie-start; replacing active span for \(key.partID) midi=\(midiNote) staff=\(staff) voice=\(voice)"
                            )
                        #endif
                        activeSpanIndexByKey[key] = nil
                    }

                    let onTick = note.tick + (performanceTimingEnabled ? (note.attackTicks ?? 0) : 0)
                    let offTick = max(onTick, note.tick + max(0, note.durationTicks))
                    let span = MusicXMLNoteSpan(
                        midiNote: midiNote,
                        staff: staff,
                        voice: voice,
                        onTick: onTick,
                        offTick: offTick
                    )
                    output.append(span)
                    activeSpanIndexByKey[key] = output.count - 1
                case .middle:
                    if let existingIndex = activeSpanIndexByKey[key] {
                        let existing = output[existingIndex]
                        output[existingIndex] = MusicXMLNoteSpan(
                            midiNote: existing.midiNote,
                            staff: existing.staff,
                            voice: existing.voice,
                            onTick: existing.onTick,
                            offTick: existing.offTick + max(0, note.durationTicks)
                        )
                    } else {
                        #if DEBUG
                            print(
                                "MusicXMLNoteSpanBuilder: tie-middle without active; starting new active span for \(key.partID) midi=\(midiNote) staff=\(staff) voice=\(voice)"
                            )
                        #endif
                        let onTick = note.tick + (performanceTimingEnabled ? (note.attackTicks ?? 0) : 0)
                        let offTick = max(onTick, note.tick + max(0, note.durationTicks))
                        let span = MusicXMLNoteSpan(
                            midiNote: midiNote,
                            staff: staff,
                            voice: voice,
                            onTick: onTick,
                            offTick: offTick
                        )
                        output.append(span)
                        activeSpanIndexByKey[key] = output.count - 1
                    }
                case .end:
                    let releaseTicks = performanceTimingEnabled ? (note.releaseTicks ?? 0) : 0
                    if let existingIndex = activeSpanIndexByKey[key] {
                        let existing = output[existingIndex]
                        output[existingIndex] = MusicXMLNoteSpan(
                            midiNote: existing.midiNote,
                            staff: existing.staff,
                            voice: existing.voice,
                            onTick: existing.onTick,
                            offTick: max(existing.onTick, existing.offTick + max(0, note.durationTicks) + releaseTicks)
                        )
                        activeSpanIndexByKey[key] = nil
                    } else {
                        #if DEBUG
                            print(
                                "MusicXMLNoteSpanBuilder: tie-end without active; creating standalone span for \(key.partID) midi=\(midiNote) staff=\(staff) voice=\(voice)"
                            )
                        #endif
                        output.append(
                            MusicXMLNoteSpan(
                                midiNote: midiNote,
                                staff: staff,
                                voice: voice,
                                onTick: note.tick + (performanceTimingEnabled ? (note.attackTicks ?? 0) : 0),
                                offTick: max(
                                    note.tick + (performanceTimingEnabled ? (note.attackTicks ?? 0) : 0),
                                    note.tick + max(0, note.durationTicks) + releaseTicks
                                )
                            )
                        )
                    }
                case .normal:
                    let attackTicks = performanceTimingEnabled ? (note.attackTicks ?? 0) : 0
                    let releaseTicks = performanceTimingEnabled ? (note.releaseTicks ?? 0) : 0
                    let onTick = note.tick + attackTicks
                    let effectiveDurationTicks = articulatedDurationTicks(for: note)
                    let offTick = max(onTick, note.tick + max(0, effectiveDurationTicks) + releaseTicks)
                    output.append(
                        MusicXMLNoteSpan(
                            midiNote: midiNote,
                            staff: staff,
                            voice: voice,
                            onTick: onTick,
                            offTick: offTick
                        )
                    )
            }
        }

        return output.sorted { lhs, rhs in
            if lhs.onTick != rhs.onTick { return lhs.onTick < rhs.onTick }
            if lhs.midiNote != rhs.midiNote { return lhs.midiNote < rhs.midiNote }
            return lhs.offTick < rhs.offTick
        }
    }

    private func articulatedDurationTicks(for note: MusicXMLNoteEvent) -> Int {
        let raw = max(0, note.durationTicks)
        guard raw > 0 else { return raw }

        let articulationMultiplier: Double = if note.articulations.contains(.staccatissimo) {
            0.25
        } else if note.articulations.contains(.staccato) {
            0.5
        } else if note.articulations.contains(.detachedLegato) {
            0.75
        } else if note.articulations.contains(.marcato) {
            0.75
        } else {
            1.0
        }

        let adjusted = Int((Double(raw) * articulationMultiplier).rounded())
        return min(raw, max(1, adjusted))
    }

    private enum Category {
        case start
        case middle
        case end
        case normal
    }
}
