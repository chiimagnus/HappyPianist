import Foundation
import MusicXML

extension MusicXMLNoteType {
    var grandStaffNoteheadGlyphToken: GrandStaffGlyphToken {
        switch self {
        case .maxima: .mensuralWhiteMaxima
        case .long: .mensuralWhiteLonga
        case .breve: .noteheadDoubleWhole
        case .whole: .noteheadWhole
        case .half: .noteheadHalf
        case .quarter, .eighth, .sixteenth, .thirtySecond, .sixtyFourth,
             .oneHundredTwentyEighth, .twoHundredFiftySixth,
             .fiveHundredTwelfth, .oneThousandTwentyFourth:
            .noteheadBlack
        }
    }

    var grandStaffRestGlyphToken: GrandStaffGlyphToken {
        switch self {
        case .maxima: .restMaxima
        case .long: .restLonga
        case .breve: .restDoubleWhole
        case .whole: .restWhole
        case .half: .restHalf
        case .quarter: .restQuarter
        case .eighth: .restEighth
        case .sixteenth: .restSixteenth
        case .thirtySecond: .restThirtySecond
        case .sixtyFourth: .restSixtyFourth
        case .oneHundredTwentyEighth: .restOneHundredTwentyEighth
        case .twoHundredFiftySixth: .restTwoHundredFiftySixth
        case .fiveHundredTwelfth: .restFiveHundredTwelfth
        case .oneThousandTwentyFourth: .restOneThousandTwentyFourth
        }
    }

    func grandStaffFlagGlyphToken(stemDirection: GrandStaffStemDirection) -> GrandStaffGlyphToken? {
        switch (self, stemDirection) {
        case (.eighth, .up): .flagEighthUp
        case (.eighth, .down): .flagEighthDown
        case (.sixteenth, .up): .flagSixteenthUp
        case (.sixteenth, .down): .flagSixteenthDown
        case (.thirtySecond, .up): .flagThirtySecondUp
        case (.thirtySecond, .down): .flagThirtySecondDown
        case (.sixtyFourth, .up): .flagSixtyFourthUp
        case (.sixtyFourth, .down): .flagSixtyFourthDown
        case (.oneHundredTwentyEighth, .up): .flagOneHundredTwentyEighthUp
        case (.oneHundredTwentyEighth, .down): .flagOneHundredTwentyEighthDown
        case (.twoHundredFiftySixth, .up): .flagTwoHundredFiftySixthUp
        case (.twoHundredFiftySixth, .down): .flagTwoHundredFiftySixthDown
        case (.fiveHundredTwelfth, .up): .flagFiveHundredTwelfthUp
        case (.fiveHundredTwelfth, .down): .flagFiveHundredTwelfthDown
        case (.oneThousandTwentyFourth, .up): .flagOneThousandTwentyFourthUp
        case (.oneThousandTwentyFourth, .down): .flagOneThousandTwentyFourthDown
        default: nil
        }
    }

    var grandStaffHasStem: Bool {
        switch self {
        case .half, .quarter, .eighth, .sixteenth, .thirtySecond, .sixtyFourth,
             .oneHundredTwentyEighth, .twoHundredFiftySixth,
             .fiveHundredTwelfth, .oneThousandTwentyFourth:
            true
        case .maxima, .long, .breve, .whole:
            false
        }
    }

    var grandStaffBeamCount: Int {
        switch self {
        case .eighth: 1
        case .sixteenth: 2
        case .thirtySecond: 3
        case .sixtyFourth: 4
        case .oneHundredTwentyEighth: 5
        case .twoHundredFiftySixth: 6
        case .fiveHundredTwelfth: 7
        case .oneThousandTwentyFourth: 8
        case .maxima, .long, .breve, .whole, .half, .quarter: 0
        }
    }
}

enum GrandStaffStemDirection: Equatable, Sendable {
    case up
    case down
}

struct GrandStaffAccidental: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
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

struct GrandStaffNotationLayout: Equatable, Sendable {
    let items: [GrandStaffNotationItem]
    let chords: [GrandStaffNotationChord]
    let rests: [GrandStaffNotationRest]
    let ties: [GrandStaffNotationTie]
    let slurs: [GrandStaffNotationSlur]
    let tuplets: [GrandStaffNotationTuplet]
    let barlines: [GrandStaffNotationBarline]
    let beams: [GrandStaffNotationBeam]
    let ledgerLines: [GrandStaffNotationLedgerLine]
    let marks: [GrandStaffNotationMark]
    let attributeChanges: [GrandStaffNotationAttributeChange]
    let context: GrandStaffNotationContext?
}

struct GrandStaffNotationChord: Equatable, Identifiable, Sendable {
    let id: String
    let tick: Int
    var xPosition: Double
    let itemIDs: [String]
    let stem: GrandStaffNotationStem
    let noteType: MusicXMLNoteType
}

struct GrandStaffNotationStem: Equatable, Sendable {
    let direction: GrandStaffStemDirection
    let isVisible: Bool
    let startItemID: String
    let endItemID: String
    let xOffset: Double
}

struct GrandStaffNotationRest: Equatable, Identifiable, Sendable {
    let id: String
    let staffNumber: Int
    let voice: Int
    let tick: Int
    var xPosition: Double
    let noteType: MusicXMLNoteType
    let durationTicks: Int
    let dotCount: Int
    let isMeasureRest: Bool
    var isHighlighted: Bool

    var glyphToken: GrandStaffGlyphToken? {
        noteType.grandStaffRestGlyphToken
    }

    var staffStep: Int {
        switch noteType {
        case .whole, .breve: 6
        default: 4
        }
    }
}

struct GrandStaffNotationTie: Equatable, Identifiable, Sendable {
    let id: String
    let staffNumber: Int
    let startTick: Int
    let endTick: Int
    let voice: Int
    let numberToken: String?
    let placementToken: String?
    var startOccurrenceID: String?
    var endOccurrenceID: String?
    var startXPosition: Double
    var endXPosition: Double
    var continuesFromPrevious: Bool
    var continuesToNext: Bool
}

struct GrandStaffNotationSlur: Equatable, Identifiable, Sendable {
    let id: String
    let staffNumber: Int
    let startTick: Int
    let endTick: Int
    let voice: Int
    let numberToken: String?
    let placementToken: String?
    var startOccurrenceID: String?
    var endOccurrenceID: String?
    var startXPosition: Double
    var endXPosition: Double
    var continuesFromPrevious: Bool
    var continuesToNext: Bool
}

struct GrandStaffNotationTuplet: Equatable, Identifiable, Sendable {
    let id: String
    let staffNumber: Int
    let startTick: Int
    let endTick: Int
    let voice: Int
    let numberToken: String?
    let displayNumber: Int?
    let bracketToken: String?
    let placementToken: String?
    var startOccurrenceID: String?
    var endOccurrenceID: String?
    var startXPosition: Double
    var endXPosition: Double
    var continuesFromPrevious: Bool
    var continuesToNext: Bool
    let nestingLevel: Int
}

struct GrandStaffNotationBarline: Equatable, Identifiable, Sendable {
    let id: String
    let tick: Int
    var xPosition: Double
}

struct GrandStaffNotationBeam: Equatable, Identifiable, Sendable {
    enum Provenance: Equatable, Sendable {
        case source(groupID: String, chordIDs: [String])
        case meterDerived
    }

    let provenance: Provenance
    let id: String
    let chordIDs: [String]
    let segments: [GrandStaffNotationBeamSegment]
}

struct GrandStaffNotationBeamSegment: Equatable, Sendable {
    enum HookDirection: Equatable, Sendable {
        case forward
        case backward
    }

    let level: Int
    let startChordID: String
    let endChordID: String
    let hookDirection: HookDirection?
}

struct GrandStaffNotationLedgerLine: Equatable, Identifiable, Sendable {
    let id: String
    let tick: Int
    var xPosition: Double
    let staffNumber: Int
    let staffStep: Int
    let minXOffsetStaffSpaces: Double
    let maxXOffsetStaffSpaces: Double
}

enum GrandStaffNotationPlacement: Equatable, Sendable {
    case above
    case below
    case left
}

struct GrandStaffNotationMark: Equatable, Identifiable, Sendable {
    enum Kind: Equatable, Sendable {
        case dynamic
        case tempo
        case text
        case pedalStart
        case pedalStop
        case pedalChange
        case pedalContinue
        case fermata
        case repeatForward
        case repeatBackward
        case endingStart
        case endingStop
        case endingDiscontinue
        case articulation(GrandStaffGlyphToken)
        case arpeggio(GrandStaffGlyphToken)
        case fingering
    }

    let id: String
    let tick: Int
    var xPosition: Double
    let staffNumber: Int
    let voice: Int
    let kind: Kind
    let text: String?
    let placement: GrandStaffNotationPlacement
    let collisionLevel: Int
    let minimumStaffStep: Int?
    let maximumStaffStep: Int?
    let minimumStaffNumber: Int?
    let maximumStaffNumber: Int?

    init(
        id: String,
        tick: Int,
        xPosition: Double,
        staffNumber: Int,
        voice: Int,
        kind: Kind,
        text: String?,
        placement: GrandStaffNotationPlacement,
        collisionLevel: Int,
        minimumStaffStep: Int?,
        maximumStaffStep: Int?,
        minimumStaffNumber: Int? = nil,
        maximumStaffNumber: Int? = nil
    ) {
        self.id = id
        self.tick = tick
        self.xPosition = xPosition
        self.staffNumber = staffNumber
        self.voice = voice
        self.kind = kind
        self.text = text
        self.placement = placement
        self.collisionLevel = collisionLevel
        self.minimumStaffStep = minimumStaffStep
        self.maximumStaffStep = maximumStaffStep
        self.minimumStaffNumber = minimumStaffNumber
        self.maximumStaffNumber = maximumStaffNumber
    }

    var glyphToken: GrandStaffGlyphToken? {
        switch kind {
        case .pedalStart: .keyboardPedalPed
        case .pedalStop, .pedalChange: .keyboardPedalUp
        case .fermata: placement == .above ? .fermataAbove : .fermataBelow
        case .dynamic, .tempo, .text, .pedalContinue,
             .repeatForward, .repeatBackward,
             .endingStart, .endingStop, .endingDiscontinue:
            nil
        case let .articulation(token), let .arpeggio(token):
            token
        case .fingering:
            nil
        }
    }
}

struct GrandStaffNotationAttributeChange: Equatable, Identifiable, Sendable {
    let id: String
    let tick: Int
    var xPosition: Double
    let staffNumber: Int
    let clefSignToken: String?
    let clefLine: Int?
    let keySignatureFifths: Int?
    let previousKeySignatureFifths: Int?
    let timeSignatureText: String?

    var clefGlyphToken: GrandStaffGlyphToken? {
        switch clefSignToken?.uppercased() {
        case "G": .gClef
        case "F": .fClef
        case "C": .cClef
        default: nil
        }
    }
}

public struct GrandStaffNotationContext: Equatable, Sendable {
    let trebleClefSymbol: String
    let bassClefSymbol: String
    let trebleClefSignToken: String?
    let trebleClefLine: Int?
    let bassClefSignToken: String?
    let bassClefLine: Int?
    let keySignatureText: String?
    let keySignatureFifths: Int?
    let timeSignatureText: String?

    var trebleClefGlyphToken: GrandStaffGlyphToken? {
        clefGlyphToken(signToken: trebleClefSignToken)
    }

    var bassClefGlyphToken: GrandStaffGlyphToken? {
        clefGlyphToken(signToken: bassClefSignToken)
    }

    public init(
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

struct GrandStaffNotationItem: Equatable, Identifiable, Sendable {
    var id: String {
        occurrenceID
    }

    let occurrenceID: String
    let staffNumber: Int
    let voice: Int
    let hand: ScoreHand
    let tick: Int
    var xPosition: Double
    let staffStep: Int
    let displayedAccidental: GrandStaffAccidental?
    var isHighlighted: Bool
    let fingerings: [MusicXMLFingering]
    let noteType: MusicXMLNoteType
    let noteheadGlyphToken: GrandStaffGlyphToken?
    let chordID: String?
    let noteheadXOffset: Double
    let accidentalXOffsetStaffSpaces: Double?
    let dotXOffsetStaffSpaces: Double?
    let dotStaffStep: Int?
    let beamID: String?
    let durationTicks: Int
    let isGrace: Bool
    let articulations: Set<MusicXMLArticulation>
    let arpeggiate: MusicXMLArpeggiate?
    let dotCount: Int

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
