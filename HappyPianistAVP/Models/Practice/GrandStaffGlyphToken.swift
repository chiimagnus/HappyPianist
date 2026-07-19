import Foundation

enum GrandStaffGlyphToken: String, CaseIterable, Equatable, Hashable, Sendable {
    case gClef
    case fClef
    case cClef
    case noteheadWhole
    case noteheadHalf
    case noteheadBlack
    case flagEighthUp
    case flagEighthDown
    case flagSixteenthUp
    case flagSixteenthDown
    case flagThirtySecondUp
    case flagThirtySecondDown
    case restWhole
    case restHalf
    case restQuarter
    case restEighth
    case restSixteenth
    case restThirtySecond
    case accidentalFlat
    case accidentalNatural
    case accidentalSharp
    case accidentalDoubleSharp
    case accidentalDoubleFlat
    case augmentationDot
    case articulationAccentAbove
    case articulationStaccatoAbove
    case articulationTenutoAbove
    case articulationStaccatissimoAbove
    case articulationMarcatoAbove
    case fermataAbove
    case fermataBelow
    case timeSignature0
    case timeSignature1
    case timeSignature2
    case timeSignature3
    case timeSignature4
    case timeSignature5
    case timeSignature6
    case timeSignature7
    case timeSignature8
    case timeSignature9

    var smuflCodePoint: UInt32 {
        switch self {
        case .gClef: 0xE050
        case .fClef: 0xE062
        case .cClef: 0xE05C
        case .noteheadWhole: 0xE0A2
        case .noteheadHalf: 0xE0A3
        case .noteheadBlack: 0xE0A4
        case .flagEighthUp: 0xE240
        case .flagEighthDown: 0xE241
        case .flagSixteenthUp: 0xE242
        case .flagSixteenthDown: 0xE243
        case .flagThirtySecondUp: 0xE244
        case .flagThirtySecondDown: 0xE245
        case .restWhole: 0xE4E3
        case .restHalf: 0xE4E4
        case .restQuarter: 0xE4E5
        case .restEighth: 0xE4E6
        case .restSixteenth: 0xE4E7
        case .restThirtySecond: 0xE4E8
        case .accidentalFlat: 0xE260
        case .accidentalNatural: 0xE261
        case .accidentalSharp: 0xE262
        case .accidentalDoubleSharp: 0xE263
        case .accidentalDoubleFlat: 0xE264
        case .augmentationDot: 0xE1E7
        case .articulationAccentAbove: 0xE4A0
        case .articulationStaccatoAbove: 0xE4A2
        case .articulationTenutoAbove: 0xE4A4
        case .articulationStaccatissimoAbove: 0xE4A6
        case .articulationMarcatoAbove: 0xE4AC
        case .fermataAbove: 0xE4C0
        case .fermataBelow: 0xE4C1
        case .timeSignature0: 0xE080
        case .timeSignature1: 0xE081
        case .timeSignature2: 0xE082
        case .timeSignature3: 0xE083
        case .timeSignature4: 0xE084
        case .timeSignature5: 0xE085
        case .timeSignature6: 0xE086
        case .timeSignature7: 0xE087
        case .timeSignature8: 0xE088
        case .timeSignature9: 0xE089
        }
    }

    var glyph: String {
        UnicodeScalar(smuflCodePoint).map(String.init) ?? ""
    }

    static func timeSignatureDigit(_ digit: Int) -> Self? {
        switch digit {
        case 0: .timeSignature0
        case 1: .timeSignature1
        case 2: .timeSignature2
        case 3: .timeSignature3
        case 4: .timeSignature4
        case 5: .timeSignature5
        case 6: .timeSignature6
        case 7: .timeSignature7
        case 8: .timeSignature8
        case 9: .timeSignature9
        default: nil
        }
    }
}
