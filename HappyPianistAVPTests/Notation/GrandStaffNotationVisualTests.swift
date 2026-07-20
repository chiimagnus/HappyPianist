import CoreGraphics
import CoreText
import CryptoKit
import Foundation
import SwiftUI
@testable import HappyPianistAVP
import Testing

@MainActor
@Test
func grandStaffNotationStandardImageRendererMatchesVisualGolden() throws {
    let model = try visualNotationModel()
    let standard = try visualSnapshot(
        model: model,
        dynamicTypeSize: .large,
        differentiateWithoutColor: false
    )
    let expected = try visualGoldenLines()[0]

    #expect(standard.description == expected)
    #expect(standard.sampledInkPixelCount > 100)
}

@MainActor
@Test
func grandStaffNotationAccessibleImageRendererMatchesVisualGolden() throws {
    let model = try visualNotationModel()
    let accessible = try visualSnapshot(
        model: model,
        dynamicTypeSize: .accessibility3,
        differentiateWithoutColor: true
    )
    let goldenLines = try visualGoldenLines()
    let expected = goldenLines[1]
    let dynamicTypeOnly = try visualSnapshot(
        model: model,
        dynamicTypeSize: .accessibility3,
        differentiateWithoutColor: false
    )
    let standard = try visualSnapshot(
        model: model,
        dynamicTypeSize: .large,
        differentiateWithoutColor: false
    )

    #expect(accessible.description == expected)
    #expect(accessible.sampledInkPixelCount > 100)
    #expect(goldenLines[0].contains(accessible.hash) == false)
    #expect(dynamicTypeOnly.hash != standard.hash)
}

private func visualGoldenLines() throws -> [String] {
    try String(
        contentsOf: testFixtureURL("NotationFidelity/visual.golden.txt"),
        encoding: .utf8
    )
    .split(whereSeparator: \.isNewline)
    .map(String.init)
}

@Test
func grandStaffNotationAccessibilityDescribesMeasureNotationAndFallbacks() throws {
    let model = try visualNotationModel()
    let layout = GrandStaffNotationLayoutService().makeLayout(
        projection: model.projection,
        overlay: model.overlay,
        measureSpans: model.score.measures,
        context: model.context,
        viewportWidthStaffSpaces: 52,
        scrollTick: 960
    )
    let descriptor = GrandStaffNotationAccessibilityDescriptor.make(
        projection: model.projection,
        layout: layout,
        measureSpans: model.score.measures,
        currentTick: 960
    )
    let labels = descriptor.elements.map(\.label)

    #expect(descriptor.containerValue.contains("第 1 小节"))
    #expect(labels.contains { $0.contains("上谱表") && $0.contains("音符") && $0.contains("当前高亮") })
    #expect(labels.contains { $0.contains("下谱表") && $0.contains("当前高亮") })
    #expect(labels.contains { $0.contains("指法 1") })
    #expect(labels.contains { $0.contains("休止符") })
    #expect(labels.contains { $0.contains("不支持的记谱内容") && $0.contains("节奏占位") })
}

private struct VisualNotationModel {
    let score: MusicXMLScore
    let projection: ScoreNotationProjection
    let overlay: ScoreNotationProjection.Overlay
    let context: GrandStaffNotationContext
}

private struct VisualSnapshot {
    let name: String
    let width: Int
    let height: Int
    let hash: String
    let sampledInkPixelCount: Int

    var description: String {
        "\(name)|\(width)x\(height)|sha256=\(hash)|sampledInk=\(sampledInkPixelCount)"
    }
}

@MainActor
private func visualSnapshot(
    model: VisualNotationModel,
    dynamicTypeSize: DynamicTypeSize,
    differentiateWithoutColor: Bool
) throws -> VisualSnapshot {
    try requireBundledBravura()
    let viewport = CGSize(width: 800, height: 320)
    let presentation = GrandStaffNotationPresentationViewModel().makePresentation(
        size: viewport,
        lineSpacing: dynamicTypeSize.isAccessibilitySize ? 22 : 14,
        projection: model.projection,
        overlay: model.overlay,
        measureSpans: model.score.measures,
        context: model.context,
        practiceHandMode: .both,
        scrollTick: 960
    )
    let content = Canvas { context, _ in
        GrandStaffNotationRenderer().draw(
            presentation: presentation,
            in: context,
            displayScale: 2,
            differentiateWithoutColor: differentiateWithoutColor
        )
    }
    .frame(width: viewport.width, height: viewport.height)
    .background(.white)
    .foregroundStyle(.black)
    .environment(\.colorScheme, .light)
    .environment(\.displayScale, 2)
    .environment(\.dynamicTypeSize, dynamicTypeSize)

    let renderer = ImageRenderer(content: content)
    renderer.proposedSize = ProposedViewSize(width: viewport.width, height: viewport.height)
    let name = differentiateWithoutColor ? "accessibility3-differentiate" : "standard"
    var snapshot: VisualSnapshot?
    renderer.render(rasterizationScale: 1) { size, render in
        let width = Int(ceil(size.width))
        let height = Int(ceil(size.height))
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let bitmap = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        ) else { return }
        bitmap.setFillColor(CGColor(gray: 1, alpha: 1))
        bitmap.fill(CGRect(x: 0, y: 0, width: width, height: height))
        render(bitmap)
        snapshot = normalizedSnapshot(name: name, bitmap: bitmap, width: width, height: height)
    }
    return try #require(snapshot)
}

private func requireBundledBravura() throws {
    let fontURL = try #require(
        Bundle.main.url(forResource: "Bravura", withExtension: "otf"),
        "Bravura.otf must be bundled in the HappyPianistAVP target before visual goldens are evaluated."
    )
    let provider = try #require(
        CGDataProvider(url: fontURL as CFURL),
        "Bravura.otf exists but cannot be opened as a font data provider."
    )
    let bundledFont = try #require(
        CGFont(provider),
        "Bravura.otf exists but is not a valid OpenType font."
    )
    try #require(
        bundledFont.postScriptName as String? == "Bravura",
        "The bundled font must use the Bravura PostScript name expected by GrandStaffNotationRenderer."
    )

    let registeredFont = CTFontCreateWithName("Bravura" as CFString, 64, nil)
    try #require(
        CTFontCopyPostScriptName(registeredFont) as String == "Bravura",
        "Bravura.otf is bundled but is not registered under the Bravura family name."
    )

    let characters = GrandStaffGlyphToken.allCases.map {
        UniChar(truncatingIfNeeded: $0.smuflCodePoint)
    }
    var glyphs = Array(repeating: CGGlyph(), count: characters.count)
    let mappedAllGlyphs = characters.withUnsafeBufferPointer { characterBuffer in
        glyphs.withUnsafeMutableBufferPointer { glyphBuffer in
            guard let characterBase = characterBuffer.baseAddress,
                  let glyphBase = glyphBuffer.baseAddress
            else {
                return false
            }
            return CTFontGetGlyphsForCharacters(
                registeredFont,
                characterBase,
                glyphBase,
                characterBuffer.count
            )
        }
    }
    try #require(
        mappedAllGlyphs && glyphs.allSatisfy { $0 != 0 },
        "The registered Bravura font does not contain the required SMuFL glyphs."
    )
}

private func normalizedSnapshot(
    name: String,
    bitmap: CGContext,
    width: Int,
    height: Int
) -> VisualSnapshot? {
    let byteCount = width * height * 4
    guard let data = bitmap.data else { return nil }
    let bytes = UnsafeRawBufferPointer(start: data, count: byteCount)

    let hash = SHA256.hash(data: Data(bytes)).map {
        let value = String($0, radix: 16)
        return value.count == 1 ? "0\(value)" : value
    }.joined()
    var sampledInkPixelCount = 0
    for offset in stride(from: 0, to: byteCount, by: 64) {
        if bytes[offset] < 250 || bytes[offset + 1] < 250 || bytes[offset + 2] < 250 {
            sampledInkPixelCount += 1
        }
    }
    return VisualSnapshot(
        name: name,
        width: width,
        height: height,
        hash: hash,
        sampledInkPixelCount: sampledInkPixelCount
    )
}

private func visualNotationModel() throws -> VisualNotationModel {
    let xml = """
    <score-partwise version="4.0">
      <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
      <part id="P1"><measure number="1">
        <attributes>
          <divisions>4</divisions><key><fifths>1</fifths></key>
          <time><beats>4</beats><beat-type>4</beat-type></time><staves>2</staves>
          <clef number="1"><sign>G</sign><line>2</line></clef>
          <clef number="2"><sign>F</sign><line>4</line></clef>
        </attributes>
        <note><pitch><step>C</step><octave>5</octave></pitch><duration>4</duration><voice>1</voice><type>quarter</type><stem>down</stem><staff>1</staff><notations><technical><fingering>1</fingering></technical></notations></note>
        <note><chord/><pitch><step>D</step><octave>5</octave></pitch><duration>4</duration><voice>1</voice><type>quarter</type><stem>down</stem><staff>1</staff></note>
        <note><pitch><step>E</step><octave>5</octave></pitch><duration>2</duration><voice>1</voice><type>eighth</type><stem>up</stem><staff>1</staff><beam number="1">begin</beam></note>
        <note><pitch><step>F</step><alter>1</alter><octave>5</octave></pitch><duration>2</duration><voice>1</voice><type>eighth</type><stem>up</stem><staff>1</staff><beam number="1">end</beam></note>
        <note><pitch><step>G</step><octave>5</octave></pitch><duration>4</duration><voice>1</voice><type>breve</type><staff>1</staff></note>
        <note><rest/><duration>4</duration><voice>1</voice><type>quarter</type><staff>1</staff></note>
        <backup><duration>16</duration></backup>
        <note><pitch><step>C</step><octave>3</octave></pitch><duration>8</duration><voice>2</voice><type>half</type><stem>up</stem><staff>2</staff></note>
        <note><rest/><duration>8</duration><voice>2</voice><type>half</type><staff>2</staff></note>
      </measure></part>
    </score-partwise>
    """
    let score = try MusicXMLParser().parse(data: Data(xml.utf8))
    let plan = makeTestScorePerformancePlan(from: score)
    let highlightedUpper = try #require(plan.noteEvents.first { $0.staff == 1 })
    let highlightedLower = try #require(plan.noteEvents.first { $0.staff == 2 })
    return VisualNotationModel(
        score: score,
        projection: ScoreNotationProjection(plan: plan, sourceScore: score),
        overlay: ScoreNotationProjection.Overlay(
            activeEventIDs: [highlightedUpper.id, highlightedLower.id],
            activeTickRange: nil
        ),
        context: GrandStaffNotationContext(keySignatureFifths: 1, timeSignatureText: "4/4")
    )
}
