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
    let staff: Int?
    let voice: Int?
    let velocity: UInt8
    let onTick: Int
    let offTick: Int
    let fingeringText: String?
    let isGrace: Bool
    let tieStart: Bool
    let tieStop: Bool
    let articulations: Set<MusicXMLArticulation>
    let arpeggiate: MusicXMLArpeggiate?
    let dotCount: Int

    init(
        occurrenceID: String,
        midiNote: Int,
        staff: Int?,
        voice: Int?,
        velocity: UInt8,
        onTick: Int,
        offTick: Int,
        fingeringText: String?,
        isGrace: Bool = false,
        tieStart: Bool = false,
        tieStop: Bool = false,
        articulations: Set<MusicXMLArticulation> = [],
        arpeggiate: MusicXMLArpeggiate? = nil,
        dotCount: Int = 0
    ) {
        self.occurrenceID = occurrenceID
        self.midiNote = midiNote
        self.staff = staff
        self.voice = voice
        self.velocity = velocity
        self.onTick = onTick
        self.offTick = offTick
        self.fingeringText = fingeringText
        self.isGrace = isGrace
        self.tieStart = tieStart
        self.tieStop = tieStop
        self.articulations = articulations
        self.arpeggiate = arpeggiate
        self.dotCount = dotCount
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

    var isRestOrGap: Bool {
        kind == .gap || (activeNotes.isEmpty && triggeredNotes.isEmpty)
    }

    var highlightedMIDINotes: Set<Int> {
        var result = Set(activeNotes.map(\.midiNote))
        result.formUnion(triggeredNotes.map(\.midiNote))
        return result
    }

    var fingeringByMIDINote: [Int: String] {
        let items = (activeNotes + triggeredNotes).compactMap { note -> (Int, String)? in
            guard let fingering = note.fingeringText, fingering.isEmpty == false else { return nil }
            return (note.midiNote, fingering)
        }
        return Dictionary(items, uniquingKeysWith: { first, _ in first })
    }
}
