import Foundation
import MusicXML

public enum PianoHighlightGuideKind: String, Equatable, Hashable, Sendable {
    case trigger
    case sustain
    case release
    case gap
}

public struct PianoHighlightNote: Equatable, Hashable, Identifiable, Sendable {
    public var id: String {
        occurrenceID
    }

    public let occurrenceID: String
    public let midiNote: Int
    public let handAssignment: ScoreHandAssignment
    public var hand: ScoreHand {
        handAssignment.hand
    }

    public let staff: Int?
    public let voice: Int?
    public let velocity: UInt8
    public let onTick: Int
    public let offTick: Int
    public let fingerings: [MusicXMLFingering]

    public init(
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

public struct PianoHighlightGuide: Equatable, Identifiable, Sendable {
    public let id: Int
    public let kind: PianoHighlightGuideKind
    public let tick: Int
    public let durationTicks: Int?
    public let practiceStepIndex: Int?
    public let activeNotes: [PianoHighlightNote]
    public let triggeredNotes: [PianoHighlightNote]
    public let releasedMIDINotes: Set<Int>

    public var highlightedMIDINotes: Set<Int> {
        var result = Set(activeNotes.map(\.midiNote))
        result.formUnion(triggeredNotes.map(\.midiNote))
        return result
    }

    public var fingeringByMIDINote: [Int: String] {
        let items = (activeNotes + triggeredNotes).compactMap { note -> (Int, String)? in
            guard let fingering = note.fingerings.fingeringDisplayText else { return nil }
            return (note.midiNote, fingering)
        }
        return Dictionary(items, uniquingKeysWith: { first, _ in first })
    }

    public init(
        id: Int,
        kind: PianoHighlightGuideKind,
        tick: Int,
        durationTicks: Int?,
        practiceStepIndex: Int?,
        activeNotes: [PianoHighlightNote],
        triggeredNotes: [PianoHighlightNote],
        releasedMIDINotes: Set<Int>
    ) {
        self.id = id
        self.kind = kind
        self.tick = tick
        self.durationTicks = durationTicks
        self.practiceStepIndex = practiceStepIndex
        self.activeNotes = activeNotes
        self.triggeredNotes = triggeredNotes
        self.releasedMIDINotes = releasedMIDINotes
    }
}
