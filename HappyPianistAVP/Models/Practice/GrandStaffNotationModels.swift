import Foundation

enum GrandStaffNoteValue: Equatable {
    case whole
    case half
    case quarter
    case eighth
    case sixteenth
    case thirtySecond
    case unsupported(sourceTypeToken: String?)

    var noteheadGlyphToken: GrandStaffGlyphToken? {
        switch self {
        case .whole: .noteheadWhole
        case .half: .noteheadHalf
        case .quarter, .eighth, .sixteenth, .thirtySecond: .noteheadBlack
        case .unsupported: nil
        }
    }

    var restGlyphToken: GrandStaffGlyphToken? {
        switch self {
        case .whole: .restWhole
        case .half: .restHalf
        case .quarter: .restQuarter
        case .eighth: .restEighth
        case .sixteenth: .restSixteenth
        case .thirtySecond: .restThirtySecond
        case .unsupported: nil
        }
    }

    func flagGlyphToken(stemDirection: GrandStaffStemDirection) -> GrandStaffGlyphToken? {
        switch (self, stemDirection) {
        case (.eighth, .up): .flagEighthUp
        case (.eighth, .down): .flagEighthDown
        case (.sixteenth, .up): .flagSixteenthUp
        case (.sixteenth, .down): .flagSixteenthDown
        case (.thirtySecond, .up): .flagThirtySecondUp
        case (.thirtySecond, .down): .flagThirtySecondDown
        default: nil
        }
    }

    var hasStem: Bool {
        switch self {
        case .half, .quarter, .eighth, .sixteenth, .thirtySecond: true
        case .whole, .unsupported: false
        }
    }
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

    var glyphToken: GrandStaffGlyphToken? {
        switch kind {
        case .sharp: .accidentalSharp
        case .flat: .accidentalFlat
        case .natural: .accidentalNatural
        case .doubleSharp: .accidentalDoubleSharp
        case .doubleFlat: .accidentalDoubleFlat
        case .unsupported: nil
        }
    }
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
    let stem: GrandStaffNotationStem
    let noteValue: GrandStaffNoteValue
}

struct GrandStaffNotationStem: Equatable {
    let direction: GrandStaffStemDirection
    let isVisible: Bool
    let startItemID: String
    let endItemID: String
    let xOffset: Double
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

    var glyphToken: GrandStaffGlyphToken? { noteValue.restGlyphToken }
    var staffStep: Int { noteValue == .whole ? 6 : 4 }
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

    var trebleClefGlyphToken: GrandStaffGlyphToken? { clefGlyphToken(signToken: trebleClefSignToken) }
    var bassClefGlyphToken: GrandStaffGlyphToken? { clefGlyphToken(signToken: bassClefSignToken) }

    init(
        trebleClefSymbol: String = GrandStaffGlyphToken.gClef.glyph,
        bassClefSymbol: String = GrandStaffGlyphToken.fClef.glyph,
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

    private func clefGlyphToken(signToken: String?) -> GrandStaffGlyphToken? {
        switch signToken?.uppercased() {
        case "G": .gClef
        case "F": .fClef
        case "C": .cClef
        default: nil
        }
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
    let fingerings: [MusicXMLFingering]
    let noteValue: GrandStaffNoteValue
    let chordID: String?
    let noteheadXOffset: Double
    let beamID: String?
    let durationTicks: Int
    let isGrace: Bool
    let articulations: Set<MusicXMLArticulation>
    let arpeggiate: MusicXMLArpeggiate?
    let dotCount: Int

    var noteheadGlyphToken: GrandStaffGlyphToken? { noteValue.noteheadGlyphToken }
    var articulationGlyphTokens: [GrandStaffGlyphToken] {
        articulations.sorted { $0.rawValue < $1.rawValue }.compactMap(\.grandStaffGlyphToken)
    }
}

private extension MusicXMLArticulation {
    var grandStaffGlyphToken: GrandStaffGlyphToken? {
        switch self {
        case .accent: .articulationAccentAbove
        case .staccato: .articulationStaccatoAbove
        case .tenuto: .articulationTenutoAbove
        case .staccatissimo: .articulationStaccatissimoAbove
        case .marcato: .articulationMarcatoAbove
        case .detachedLegato: nil
        }
    }
}
