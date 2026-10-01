import CoreText
import Foundation
import SwiftUI

struct GrandStaffGlyphBounds: Equatable, Sendable {
    let minX: Double
    let minY: Double
    let maxX: Double
    let maxY: Double

    var width: Double {
        maxX - minX
    }

    var height: Double {
        maxY - minY
    }
}

struct GrandStaffEngravingMetrics: Equatable {
    // All values are expressed in staff spaces; the viewport applies the display scale once.
    let smuflEmSize = 4.0
    let graceNoteScale = 0.70
    let staffLineThickness = 0.13
    let stemThickness = 0.12
    let beamThickness = 0.50
    let beamSpacing = 0.75
    let ledgerLineThickness = 0.16
    let ledgerLineExtension = 0.40
    let defaultStemLength = 3.50
    let maximumBeamCount = 8
    let accidentalNoteheadGap = 0.25
    let accidentalColumnGap = 0.20
    let dotNoteheadGap = 0.35
    let dotSpacing = 0.55

    func textFont(size: CGFloat, bold: Bool = false, italic: Bool = false) -> CTFont {
        var style = Font.caption
        if bold { style = style.bold() }
        if italic { style = style.italic() }
        let base = style.resolve(in: EnvironmentValues().fontResolutionContext).ctFont
        return CTFontCreateCopyWithAttributes(base, size, nil, nil)
    }

    var noteheadViewportBounds: GrandStaffGlyphBounds {
        GrandStaffGlyphBounds(minX: -0.844, minY: -0.50, maxX: 0.844, maxY: 0.50)
    }

    let noteheadColumnWidth = 1.18

    func glyphScale(isGrace: Bool) -> Double {
        isGrace ? graceNoteScale : 1
    }

    func bounds(for token: GrandStaffGlyphToken) -> GrandStaffGlyphBounds? {
        switch token {
        case .brace:
            GrandStaffGlyphBounds(minX: 0.008, minY: 0, maxX: 0.328, maxY: 3.988)
        case .gClef:
            GrandStaffGlyphBounds(minX: 0, minY: -2.632, maxX: 2.684, maxY: 4.392)
        case .fClef:
            GrandStaffGlyphBounds(minX: -0.02, minY: -2.54, maxX: 2.736, maxY: 1.048)
        case .cClef:
            GrandStaffGlyphBounds(minX: 0, minY: -2.024, maxX: 2.796, maxY: 2.024)
        case .flagEighthUp:
            GrandStaffGlyphBounds(minX: 0, minY: -3.252, maxX: 1.056, maxY: 0.036)
        case .flagEighthDown:
            GrandStaffGlyphBounds(minX: 0, minY: -0.056, maxX: 1.224, maxY: 3.232)
        case .flagSixteenthUp:
            GrandStaffGlyphBounds(minX: 0, minY: -3.252, maxX: 1.116, maxY: 0.008)
        case .flagSixteenthDown:
            GrandStaffGlyphBounds(minX: 0, minY: -0.036, maxX: 1.188, maxY: 3.252)
        case .flagThirtySecondUp:
            GrandStaffGlyphBounds(minX: 0, minY: -3.248, maxX: 1.044, maxY: 0.596)
        case .flagThirtySecondDown:
            GrandStaffGlyphBounds(minX: 0, minY: -0.688, maxX: 1.092, maxY: 3.248)
        case .flagSixtyFourthUp:
            GrandStaffGlyphBounds(minX: 0, minY: -3.248, maxX: 1.044, maxY: 1.388)
        case .flagSixtyFourthDown:
            GrandStaffGlyphBounds(minX: 0, minY: -1.504, maxX: 1.092, maxY: 3.248)
        case .flagOneHundredTwentyEighthUp:
            GrandStaffGlyphBounds(minX: 0, minY: -3.248, maxX: 1.044, maxY: 2.132)
        case .flagOneHundredTwentyEighthDown:
            GrandStaffGlyphBounds(minX: 0, minY: -2.32, maxX: 1.092, maxY: 3.248)
        case .flagTwoHundredFiftySixthUp:
            GrandStaffGlyphBounds(minX: 0, minY: -3.248, maxX: 1.056, maxY: 2.816)
        case .flagTwoHundredFiftySixthDown:
            GrandStaffGlyphBounds(minX: 0, minY: -3.004, maxX: 1.196, maxY: 3.252)
        case .flagFiveHundredTwelfthUp:
            GrandStaffGlyphBounds(minX: 0, minY: -3.248, maxX: 1.06, maxY: 3.564)
        case .flagFiveHundredTwelfthDown:
            GrandStaffGlyphBounds(minX: 0, minY: -3.756, maxX: 1.2, maxY: 3.248)
        case .flagOneThousandTwentyFourthUp:
            GrandStaffGlyphBounds(minX: 0, minY: -3.248, maxX: 1.06, maxY: 4.316)
        case .flagOneThousandTwentyFourthDown:
            GrandStaffGlyphBounds(minX: 0, minY: -4.808, maxX: 1.204, maxY: 2.972)
        case .mensuralWhiteMaxima:
            GrandStaffGlyphBounds(minX: -1.25, minY: -3.548, maxX: 1.25, maxY: 0.684)
        case .mensuralWhiteLonga:
            GrandStaffGlyphBounds(minX: -0.65, minY: -3.548, maxX: 0.65, maxY: 0.684)
        case .noteheadDoubleWhole:
            GrandStaffGlyphBounds(minX: -1.198, minY: -0.62, maxX: 1.198, maxY: 0.62)
        case .noteheadWhole:
            noteheadViewportBounds
        case .noteheadHalf, .noteheadBlack:
            GrandStaffGlyphBounds(minX: -0.59, minY: -0.50, maxX: 0.59, maxY: 0.50)
        case .augmentationDot:
            GrandStaffGlyphBounds(minX: -0.20, minY: -0.20, maxX: 0.20, maxY: 0.20)
        case .accidentalFlat:
            GrandStaffGlyphBounds(minX: -0.452, minY: -0.70, maxX: 0.452, maxY: 1.756)
        case .accidentalNatural:
            GrandStaffGlyphBounds(minX: -0.336, minY: -1.34, maxX: 0.336, maxY: 1.364)
        case .accidentalSharp:
            GrandStaffGlyphBounds(minX: -0.498, minY: -1.392, maxX: 0.498, maxY: 1.40)
        case .accidentalDoubleSharp:
            GrandStaffGlyphBounds(minX: -0.494, minY: -0.50, maxX: 0.494, maxY: 0.508)
        case .accidentalDoubleFlat:
            GrandStaffGlyphBounds(minX: -0.822, minY: -0.70, maxX: 0.822, maxY: 1.748)
        case .restMaxima:
            GrandStaffGlyphBounds(minX: -0.762, minY: -0.996, maxX: 0.762, maxY: 1)
        case .restLonga:
            GrandStaffGlyphBounds(minX: -0.25, minY: -0.996, maxX: 0.25, maxY: 1)
        case .restDoubleWhole:
            GrandStaffGlyphBounds(minX: -0.25, minY: 0, maxX: 0.25, maxY: 1)
        case .restWhole:
            GrandStaffGlyphBounds(minX: -0.564, minY: -0.54, maxX: 0.564, maxY: 0.036)
        case .restHalf:
            GrandStaffGlyphBounds(minX: -0.564, minY: -0.008, maxX: 0.564, maxY: 0.568)
        case .restQuarter:
            GrandStaffGlyphBounds(minX: -0.538, minY: -1.50, maxX: 0.538, maxY: 1.492)
        case .restEighth:
            GrandStaffGlyphBounds(minX: -0.494, minY: -1.004, maxX: 0.494, maxY: 0.696)
        case .restSixteenth:
            GrandStaffGlyphBounds(minX: -0.64, minY: -2.0, maxX: 0.64, maxY: 0.716)
        case .restThirtySecond:
            GrandStaffGlyphBounds(minX: -0.726, minY: -2.0, maxX: 0.726, maxY: 1.704)
        case .restSixtyFourth:
            GrandStaffGlyphBounds(minX: -0.78, minY: -2.0, maxX: 0.78, maxY: 2.70)
        case .restOneHundredTwentyEighth:
            GrandStaffGlyphBounds(minX: -0.82, minY: -2.0, maxX: 0.82, maxY: 3.70)
        case .restTwoHundredFiftySixth:
            GrandStaffGlyphBounds(minX: -1.082, minY: -4, maxX: 1.082, maxY: 2.784)
        case .restFiveHundredTwelfth:
            GrandStaffGlyphBounds(minX: -1.208, minY: -4, maxX: 1.208, maxY: 3.776)
        case .restOneThousandTwentyFourth:
            GrandStaffGlyphBounds(minX: -1.336, minY: -3.972, maxX: 1.336, maxY: 4.788)
        case .articulationAccentAbove:
            GrandStaffGlyphBounds(minX: -0.678, minY: -0.49, maxX: 0.678, maxY: 0.49)
        case .articulationStaccatoAbove:
            GrandStaffGlyphBounds(minX: -0.168, minY: -0.168, maxX: 0.168, maxY: 0.168)
        case .articulationTenutoAbove:
            GrandStaffGlyphBounds(minX: -0.592, minY: -0.09, maxX: 0.592, maxY: 0.09)
        case .articulationStaccatissimoAbove:
            GrandStaffGlyphBounds(minX: -0.168, minY: -0.02, maxX: 0.168, maxY: 0.872)
        case .articulationMarcatoAbove:
            GrandStaffGlyphBounds(minX: -0.72, minY: -0.03, maxX: 0.72, maxY: 1.012)
        case .fermataAbove, .fermataBelow:
            GrandStaffGlyphBounds(minX: -1.21, minY: -0.658, maxX: 1.21, maxY: 0.658)
        case .arpeggiato:
            GrandStaffGlyphBounds(minX: 0, minY: 0.036, maxX: 0.486, maxY: 5.47)
        case .arpeggiatoUp, .arpeggiatoDown:
            GrandStaffGlyphBounds(minX: 0, minY: -0.016, maxX: 0.916, maxY: 6.044)
        case .keyboardPedalPed:
            GrandStaffGlyphBounds(minX: 0, minY: -0.032, maxX: 4.076, maxY: 2.22)
        case .keyboardPedalUp:
            GrandStaffGlyphBounds(minX: 0, minY: 0, maxX: 1.8, maxY: 1.8)
        case .timeSignature0, .timeSignature1, .timeSignature2, .timeSignature3,
             .timeSignature4, .timeSignature5, .timeSignature6, .timeSignature7,
             .timeSignature8, .timeSignature9:
            GrandStaffGlyphBounds(minX: 0.08, minY: -1.036, maxX: 1.8, maxY: 1.036)
        }
    }
}
