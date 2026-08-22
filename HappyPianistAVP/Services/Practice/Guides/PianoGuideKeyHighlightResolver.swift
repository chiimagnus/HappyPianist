import Foundation
import Practice

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
        // 一枚物理琴键只能使用一种纯色；两谱表同时包含时使用中性色。
        guard staffNumbers.count == 1 else { return nil }
        return staffNumbers.first
    }
}
