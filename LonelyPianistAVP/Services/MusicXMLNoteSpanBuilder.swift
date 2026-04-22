import Foundation

struct MusicXMLNoteSpanBuilder {
    private struct Key: Hashable {
        let partID: String
        let midiNote: Int
        let staff: Int
        let voice: Int
    }

    func buildSpans(from notes: [MusicXMLNoteEvent]) -> [MusicXMLNoteSpan] {
        let orderedNotes = notes.sorted { lhs, rhs in
            if lhs.tick != rhs.tick { return lhs.tick < rhs.tick }
            return (lhs.midiNote ?? -1) < (rhs.midiNote ?? -1)
        }

        var output: [MusicXMLNoteSpan] = []
        output.reserveCapacity(orderedNotes.count)

        var activeSpanIndexByKey: [Key: Int] = [:]

        for note in orderedNotes {
            guard note.isRest == false else { continue }
            guard let midiNote = note.midiNote else { continue }

            let staff = note.staff ?? 1
            let voice = note.voice ?? 1
            let key = Key(partID: note.partID, midiNote: midiNote, staff: staff, voice: voice)

            let category: Category
            if note.tieStart, note.tieStop {
                category = .middle
            } else if note.tieStart {
                category = .start
            } else if note.tieStop {
                category = .end
            } else {
                category = .normal
            }

            switch category {
                case .start:
                    if activeSpanIndexByKey[key] != nil {
                        #if DEBUG
                        print("MusicXMLNoteSpanBuilder: duplicate tie-start; replacing active span for \(key.partID) midi=\(midiNote) staff=\(staff) voice=\(voice)")
                        #endif
                        activeSpanIndexByKey[key] = nil
                    }

                    let span = MusicXMLNoteSpan(
                        midiNote: midiNote,
                        staff: staff,
                        voice: voice,
                        onTick: note.tick,
                        offTick: note.tick + max(0, note.durationTicks)
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
                        print("MusicXMLNoteSpanBuilder: tie-middle without active; starting new active span for \(key.partID) midi=\(midiNote) staff=\(staff) voice=\(voice)")
                        #endif
                        let span = MusicXMLNoteSpan(
                            midiNote: midiNote,
                            staff: staff,
                            voice: voice,
                            onTick: note.tick,
                            offTick: note.tick + max(0, note.durationTicks)
                        )
                        output.append(span)
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
                            offTick: existing.offTick + max(0, note.durationTicks)
                        )
                        activeSpanIndexByKey[key] = nil
                    } else {
                        #if DEBUG
                        print("MusicXMLNoteSpanBuilder: tie-end without active; creating standalone span for \(key.partID) midi=\(midiNote) staff=\(staff) voice=\(voice)")
                        #endif
                        output.append(
                            MusicXMLNoteSpan(
                                midiNote: midiNote,
                                staff: staff,
                                voice: voice,
                                onTick: note.tick,
                                offTick: note.tick + max(0, note.durationTicks)
                            )
                        )
                    }
                case .normal:
                    output.append(
                        MusicXMLNoteSpan(
                            midiNote: midiNote,
                            staff: staff,
                            voice: voice,
                            onTick: note.tick,
                            offTick: note.tick + max(0, note.durationTicks)
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

    private enum Category {
        case start
        case middle
        case end
        case normal
    }
}
