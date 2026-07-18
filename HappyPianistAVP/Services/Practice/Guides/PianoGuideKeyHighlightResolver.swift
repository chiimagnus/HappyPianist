import Foundation

struct PianoGuideKeyHighlightResolver {
    func resolveHighlights(guide: PianoHighlightGuide) -> [Int: PianoGuideKeyHighlight] {
        var triggeredNotesByMidi: [Int: [PianoHighlightNote]] = [:]
        for note in guide.triggeredNotes {
            triggeredNotesByMidi[note.midiNote, default: []].append(note)
        }
        let triggeredMIDINotes = Set(triggeredNotesByMidi.keys)

        var activeNotesByMidi: [Int: [PianoHighlightNote]] = [:]
        for note in guide.activeNotes {
            activeNotesByMidi[note.midiNote, default: []].append(note)
        }

        return Dictionary(uniqueKeysWithValues: guide.highlightedMIDINotes.map { midiNote in
            let phase: PianoGuideHighlightPhase = triggeredMIDINotes.contains(midiNote) ? .triggered : .active
            let sourceNotes = triggeredNotesByMidi[midiNote] ?? activeNotesByMidi[midiNote] ?? []
            return (
                midiNote,
                PianoGuideKeyHighlight(
                    midiNote: midiNote,
                    phase: phase,
                    staffNumber: Self.resolvedStaffNumber(notes: sourceNotes)
                )
            )
        })
    }

    private static func resolvedStaffNumber(notes: [PianoHighlightNote]) -> Int? {
        let staffNumbers = Set(notes.compactMap(\.staff))
        // ponytail: one physical key gets one solid tint; use neutral if both staves contain it simultaneously.
        guard staffNumbers.count == 1 else { return nil }
        return staffNumbers.first
    }
}
