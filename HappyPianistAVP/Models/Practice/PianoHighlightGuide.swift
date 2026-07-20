import Foundation

enum PianoHighlightGuideKind: String, Equatable, Hashable {
    case trigger
    case sustain
    case release
    case gap
}

struct PianoHighlightNote: Equatable, Hashable, Identifiable {
    var id: String {
        occurrenceID
    }

    let occurrenceID: String
    let midiNote: Int
    let handAssignment: ScoreHandAssignment
    var hand: ScoreHand { handAssignment.hand }
    let staff: Int?
    let voice: Int?
    let velocity: UInt8
    let onTick: Int
    let offTick: Int
    let fingerings: [MusicXMLFingering]

    init(
        occurrenceID: String,
        midiNote: Int,
        staff: Int?,
        voice: Int?,
        velocity: UInt8,
        onTick: Int,
        offTick: Int,
        fingerings: [MusicXMLFingering],
        handAssignment: ScoreHandAssignment
    ) {
        self.occurrenceID = occurrenceID
        self.midiNote = midiNote
        self.staff = staff
        self.voice = voice
        self.velocity = velocity
        self.onTick = onTick
        self.offTick = offTick
        self.fingerings = fingerings
        self.handAssignment = handAssignment
    }
}

struct PianoHighlightGuide: Equatable, Identifiable {
    let id: Int
    let kind: PianoHighlightGuideKind
    let tick: Int
    let durationTicks: Int?
    let practiceStepIndex: Int?
    let activeNotes: [PianoHighlightNote]
    let triggeredNotes: [PianoHighlightNote]
    let releasedMIDINotes: Set<Int>

    var highlightedMIDINotes: Set<Int> {
        var result = Set(activeNotes.map(\.midiNote))
        result.formUnion(triggeredNotes.map(\.midiNote))
        return result
    }

    var fingeringByMIDINote: [Int: String] {
        let items = (activeNotes + triggeredNotes).compactMap { note -> (Int, String)? in
            guard let fingering = note.fingerings.fingeringDisplayText else { return nil }
            return (note.midiNote, fingering)
        }
        return Dictionary(items, uniquingKeysWith: { first, _ in first })
    }
}
