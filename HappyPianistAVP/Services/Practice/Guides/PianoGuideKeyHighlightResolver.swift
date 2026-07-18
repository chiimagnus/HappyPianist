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
            let preferredHand = triggeredNotesByMidi[midiNote].flatMap(Self.resolvedHand)
                ?? activeNotesByMidi[midiNote].flatMap(Self.resolvedHand)
                ?? .unknown
            return (midiNote, PianoGuideKeyHighlight(midiNote: midiNote, phase: phase, hand: preferredHand))
        })
    }

    private static func resolvedHand(notes: [PianoHighlightNote]) -> ScoreHand? {
        guard notes.isEmpty == false else { return nil }
        if notes.contains(where: { $0.hand == .left }) { return .left }
        if notes.contains(where: { $0.hand == .right }) { return .right }
        return .unknown
    }
}
