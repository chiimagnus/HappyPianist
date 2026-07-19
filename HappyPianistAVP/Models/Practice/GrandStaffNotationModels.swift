import Foundation

enum GrandStaffNoteValue: Equatable {
    case whole
    case half
    case quarter
    case eighth
    case sixteenth
    case thirtySecond
    case unsupported(sourceTypeToken: String?)
}

enum GrandStaffStemDirection: Equatable {
    case up
    case down
}

struct GrandStaffAccidental: Equatable {
    enum Kind: Equatable {
        case sharp
        case flat
        case natural
        case doubleSharp
        case doubleFlat
        case unsupported
    }

    let kind: Kind
    let sourceToken: String?
    let alter: Double
}

struct GrandStaffNotationLayout: Equatable {
    let items: [GrandStaffNotationItem]
    let chords: [GrandStaffNotationChord]
    let rests: [GrandStaffNotationRest]
    let ties: [GrandStaffNotationTie]
    let slurs: [GrandStaffNotationSlur]
    let tuplets: [GrandStaffNotationTuplet]
    let barlines: [GrandStaffNotationBarline]
    let beams: [GrandStaffNotationBeam]
    let context: GrandStaffNotationContext?
}

struct GrandStaffNotationChord: Equatable, Identifiable {
    let id: String
    let tick: Int
    let xPosition: Double
    let itemIDs: [String]
    let stemDirection: GrandStaffStemDirection
    let noteValue: GrandStaffNoteValue
}

struct GrandStaffNotationRest: Equatable, Identifiable {
    let id: String
    let staffNumber: Int
    let voice: Int
    let guideID: Int
    let tick: Int
    let xPosition: Double
    let noteValue: GrandStaffNoteValue
    let dotCount: Int
    let isHighlighted: Bool
}

struct GrandStaffNotationTie: Equatable, Identifiable {
    let id: String
    let staffNumber: Int
    let voice: Int
    let numberToken: String?
    let placementToken: String?
    let startOccurrenceID: String?
    let endOccurrenceID: String?
    let startXPosition: Double
    let endXPosition: Double
    let continuesFromPrevious: Bool
    let continuesToNext: Bool
}

struct GrandStaffNotationSlur: Equatable, Identifiable {
    let id: String
    let staffNumber: Int
    let voice: Int
    let numberToken: String?
    let placementToken: String?
    let startOccurrenceID: String?
    let endOccurrenceID: String?
    let startXPosition: Double
    let endXPosition: Double
    let continuesFromPrevious: Bool
    let continuesToNext: Bool
}

struct GrandStaffNotationTuplet: Equatable, Identifiable {
    let id: String
    let staffNumber: Int
    let voice: Int
    let numberToken: String?
    let bracketToken: String?
    let placementToken: String?
    let startOccurrenceID: String?
    let endOccurrenceID: String?
    let startXPosition: Double
    let endXPosition: Double
    let continuesFromPrevious: Bool
    let continuesToNext: Bool
}

struct GrandStaffNotationBarline: Equatable, Identifiable {
    let id: String
    let tick: Int
    let xPosition: Double
}

struct GrandStaffNotationBeam: Equatable, Identifiable {
    let id: String
    let chordIDs: [String]
    let beamCount: Int
}

struct GrandStaffNotationContext: Equatable {
    let trebleClefSymbol: String
    let bassClefSymbol: String
    let trebleClefSignToken: String?
    let trebleClefLine: Int?
    let bassClefSignToken: String?
    let bassClefLine: Int?
    let keySignatureText: String?
    let keySignatureFifths: Int?
    let timeSignatureText: String?

    init(
        trebleClefSymbol: String = "\u{E050}",
        bassClefSymbol: String = "\u{E062}",
        trebleClefSignToken: String? = "G",
        trebleClefLine: Int? = 2,
        bassClefSignToken: String? = "F",
        bassClefLine: Int? = 4,
        keySignatureText: String? = nil,
        keySignatureFifths: Int? = nil,
        timeSignatureText: String? = nil
    ) {
        self.trebleClefSymbol = trebleClefSymbol
        self.bassClefSymbol = bassClefSymbol
        self.trebleClefSignToken = trebleClefSignToken
        self.trebleClefLine = trebleClefLine
        self.bassClefSignToken = bassClefSignToken
        self.bassClefLine = bassClefLine
        self.keySignatureText = keySignatureText
        self.keySignatureFifths = keySignatureFifths
        self.timeSignatureText = timeSignatureText
    }
}

struct GrandStaffNotationItem: Equatable, Identifiable {
    var id: String {
        occurrenceID
    }

    let occurrenceID: String
    let staffNumber: Int
    let voice: Int
    let hand: ScoreHand
    let guideID: Int
    let tick: Int
    let xPosition: Double
    let staffStep: Int
    let displayedAccidental: GrandStaffAccidental?
    let isHighlighted: Bool
    let fingeringText: String?
    let noteValue: GrandStaffNoteValue
    let chordID: String?
    let noteHeadXOffset: Double
    let stemDirection: GrandStaffStemDirection
    let beamID: String?
    let durationTicks: Int
    let isGrace: Bool
    let articulations: Set<MusicXMLArticulation>
    let arpeggiate: MusicXMLArpeggiate?
    let dotCount: Int
}
