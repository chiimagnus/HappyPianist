import Foundation

enum ScrollingStaffNoteValue: Equatable {
    case whole
    case half
    case quarter
    case eighth
    case sixteenth
    case thirtySecond
}

enum ScrollingStaffStemDirection: Equatable {
    case up
    case down
}

struct ScrollingStaffNotationLayout: Equatable {
    let items: [ScrollingStaffNotationItem]
    let chords: [ScrollingStaffNotationChord]
    let rests: [ScrollingStaffNotationRest]
    let barlines: [ScrollingStaffNotationBarline]
    let beams: [ScrollingStaffNotationBeam]
    let context: ScrollingStaffNotationContext?
}

struct ScrollingStaffNotationChord: Equatable, Identifiable {
    let id: String
    let tick: Int
    let xPosition: Double
    let itemIDs: [String]
    let stemDirection: ScrollingStaffStemDirection
    let noteValue: ScrollingStaffNoteValue
}

struct ScrollingStaffNotationRest: Equatable, Identifiable {
    let id: String
    let guideID: Int
    let tick: Int
    let xPosition: Double
    let noteValue: ScrollingStaffNoteValue
    let isHighlighted: Bool
}

struct ScrollingStaffNotationBarline: Equatable, Identifiable {
    let id: String
    let tick: Int
    let xPosition: Double
}

struct ScrollingStaffNotationBeam: Equatable, Identifiable {
    let id: String
    let chordIDs: [String]
    let beamCount: Int
}

struct ScrollingStaffNotationContext: Equatable {
    let clefSymbol: String
    let keySignatureText: String?
    let keySignatureFifths: Int?
    let timeSignatureText: String?

    init(
        clefSymbol: String = "𝄞",
        keySignatureText: String? = nil,
        keySignatureFifths: Int? = nil,
        timeSignatureText: String? = nil
    ) {
        self.clefSymbol = clefSymbol
        self.keySignatureText = keySignatureText
        self.keySignatureFifths = keySignatureFifths
        self.timeSignatureText = timeSignatureText
    }
}

struct ScrollingStaffNotationItem: Equatable, Identifiable {
    var id: String {
        occurrenceID
    }

    let occurrenceID: String
    let midiNote: Int
    let guideID: Int
    let tick: Int
    let xPosition: Double
    let staff: Int?
    let voice: Int?
    let staffStep: Int
    let showsSharpAccidental: Bool
    let isHighlighted: Bool
    let fingeringText: String?
    let noteValue: ScrollingStaffNoteValue
    let chordID: String?
    let noteHeadXOffset: Double
    let stemDirection: ScrollingStaffStemDirection
    let beamID: String?
    let durationTicks: Int
    let isGrace: Bool
    let tieStart: Bool
    let tieStop: Bool
    let tieEndXPosition: Double?
    let articulations: Set<MusicXMLArticulation>
    let arpeggiate: MusicXMLArpeggiate?
    let dotCount: Int

    var usesOpenNoteHead: Bool {
        (noteValue == .whole || noteValue == .half) && isGrace == false
    }

    var hasStem: Bool {
        noteValue != .whole
    }

    var hasFlag: Bool {
        (noteValue == .eighth || noteValue == .sixteenth || noteValue == .thirtySecond) && beamID == nil
    }
}
