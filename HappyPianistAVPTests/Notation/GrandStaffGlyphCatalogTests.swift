import CoreGraphics
@testable import HappyPianistAVP
import Testing

@Test
func glyphCatalogKeepsSupportedSMuFLCodePointsCentralized() {
    let snapshot = GrandStaffGlyphToken.allCases.map {
        "\($0.rawValue)=\(String($0.smuflCodePoint, radix: 16).uppercased())"
    }

    #expect(snapshot == [
        "brace=E000", "gClef=E050", "fClef=E062", "cClef=E05C",
        "noteheadWhole=E0A2", "noteheadHalf=E0A3", "noteheadBlack=E0A4",
        "flagEighthUp=E240", "flagEighthDown=E241",
        "flagSixteenthUp=E242", "flagSixteenthDown=E243",
        "flagThirtySecondUp=E244", "flagThirtySecondDown=E245",
        "restWhole=E4E3", "restHalf=E4E4", "restQuarter=E4E5",
        "restEighth=E4E6", "restSixteenth=E4E7", "restThirtySecond=E4E8",
        "accidentalFlat=E260", "accidentalNatural=E261", "accidentalSharp=E262",
        "accidentalDoubleSharp=E263", "accidentalDoubleFlat=E264", "augmentationDot=E1E7",
        "articulationAccentAbove=E4A0", "articulationStaccatoAbove=E4A2",
        "articulationTenutoAbove=E4A4", "articulationStaccatissimoAbove=E4A6",
        "articulationMarcatoAbove=E4AC", "fermataAbove=E4C0", "fermataBelow=E4C1",
        "arpeggiato=E63C", "arpeggiatoUp=E634", "arpeggiatoDown=E635",
        "keyboardPedalPed=E650", "keyboardPedalUp=E655",
        "timeSignature0=E080", "timeSignature1=E081", "timeSignature2=E082",
        "timeSignature3=E083", "timeSignature4=E084", "timeSignature5=E085",
        "timeSignature6=E086", "timeSignature7=E087", "timeSignature8=E088",
        "timeSignature9=E089",
    ])
    #expect(GrandStaffGlyphToken.allCases.allSatisfy { $0.glyph.unicodeScalars.first?.value == $0.smuflCodePoint })
}

@Test
func timeSignatureDigitsResolveThroughCatalog() {
    #expect((0 ... 9).compactMap(GrandStaffGlyphToken.timeSignatureDigit).map(\.smuflCodePoint) ==
        Array(0xE080 ... 0xE089))
    #expect(GrandStaffGlyphToken.timeSignatureDigit(-1) == nil)
    #expect(GrandStaffGlyphToken.timeSignatureDigit(10) == nil)
}

@Test
func notationModelResolvesHeadsFlagsRestsAndAccidentalsThroughCatalog() {
    let values: [GrandStaffNoteValue] = [
        .whole, .half, .quarter, .eighth, .sixteenth, .thirtySecond,
    ]
    #expect(values.compactMap(\.noteheadGlyphToken) == [
        .noteheadWhole, .noteheadHalf, .noteheadBlack, .noteheadBlack, .noteheadBlack, .noteheadBlack,
    ])
    #expect(values.compactMap(\.restGlyphToken) == [
        .restWhole, .restHalf, .restQuarter, .restEighth, .restSixteenth, .restThirtySecond,
    ])
    #expect(values.compactMap { $0.flagGlyphToken(stemDirection: .up) } == [
        .flagEighthUp, .flagSixteenthUp, .flagThirtySecondUp,
    ])
    #expect(values.compactMap { $0.flagGlyphToken(stemDirection: .down) } == [
        .flagEighthDown, .flagSixteenthDown, .flagThirtySecondDown,
    ])

    let accidentals: [GrandStaffAccidental.Kind] = [
        .sharp, .flat, .natural, .doubleSharp, .doubleFlat, .unsupported,
    ]
    #expect(accidentals.map {
        GrandStaffAccidental(kind: $0, sourceToken: nil, alter: 0).glyphToken
    } == [
        .accidentalSharp, .accidentalFlat, .accidentalNatural,
        .accidentalDoubleSharp, .accidentalDoubleFlat, nil,
    ])
    #expect(GrandStaffNoteValue.unsupported(sourceTypeToken: "breve").noteheadGlyphToken == nil)
}

@Test
func engravingMetricsStayInStaffSpaceUnits() {
    let metrics = GrandStaffEngravingMetrics()
    let black = metrics.bounds(for: .noteheadBlack)
    let whole = metrics.bounds(for: .noteheadWhole)

    #expect(metrics.staffLineThickness == 0.13)
    #expect(metrics.stemThickness == 0.12)
    #expect(metrics.beamThickness == 0.50)
    #expect(metrics.ledgerLineExtension == 0.40)
    #expect(metrics.defaultStemLength == 3.50)
    #expect(metrics.noteheadColumnWidth == 1.18)
    #expect(metrics.smuflEmSize == 4)
    #expect(metrics.glyphScale(isGrace: false) == 1)
    #expect(metrics.glyphScale(isGrace: true) == 0.70)
    #expect(black?.width == 1.18)
    #expect(black?.height == 1.0)
    #expect((whole?.width ?? 0) > (black?.width ?? 0))
    #expect(metrics.bounds(for: .accidentalSharp) == .init(
        minX: -0.498,
        minY: -1.392,
        maxX: 0.498,
        maxY: 1.4
    ))
    #expect(metrics.bounds(for: .augmentationDot) == .init(
        minX: -0.2,
        minY: -0.2,
        maxX: 0.2,
        maxY: 0.2
    ))
    #expect(metrics.bounds(for: .gClef) == nil)
}

@Test
func rhythmicGlyphsExposeStemEligibilityAndViewportBounds() {
    #expect(GrandStaffNoteValue.whole.hasStem == false)
    #expect(GrandStaffNoteValue.half.hasStem)
    #expect(GrandStaffNoteValue.quarter.hasStem)
    #expect(GrandStaffNoteValue.eighth.hasStem)
    #expect(GrandStaffNoteValue.sixteenth.hasStem)
    #expect(GrandStaffNoteValue.thirtySecond.hasStem)
    #expect(GrandStaffNoteValue.unsupported(sourceTypeToken: "breve").hasStem == false)

    let metrics = GrandStaffEngravingMetrics()
    let layout = GrandStaffNotationViewportLayoutService().makeLayout(
        size: CGSize(width: 800, height: 220),
        lineSpacing: 14,
        items: [],
        context: nil
    )
    #expect(abs(layout.noteWidth - 14 * metrics.noteheadViewportBounds.width) < 0.0001)
    #expect(abs(layout.noteHeight - 14 * metrics.noteheadViewportBounds.height) < 0.0001)
    #expect(abs(layout.smuflFontSize - 14 * metrics.smuflEmSize) < 0.0001)
    #expect(abs(layout.noteheadColumnWidth - 14 * metrics.noteheadColumnWidth) < 0.0001)
    #expect(layout.requiredHeight > layout.bassBottomLineY + layout.canvasYOffset)
}
