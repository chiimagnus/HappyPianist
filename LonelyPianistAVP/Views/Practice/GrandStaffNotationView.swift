import SwiftUI

struct GrandStaffNotationView: View {
    let guides: [PianoHighlightGuide]
    let currentGuide: PianoHighlightGuide?
    let measureSpans: [MusicXMLMeasureSpan]
    let context: GrandStaffNotationContext?
    var scrollTickProvider: (() -> Double?)?

    private let layoutService: any GrandStaffNotationLayoutServiceProtocol
    private let viewportLayoutService: any GrandStaffNotationViewportLayoutServiceProtocol
    private let fixedLineSpacing: CGFloat = 14
    @Environment(\.displayScale) private var displayScale
    @State private var centeredForFirstGuideID: Int?

    init(
        guides: [PianoHighlightGuide],
        currentGuide: PianoHighlightGuide?,
        measureSpans: [MusicXMLMeasureSpan],
        context: GrandStaffNotationContext?,
        scrollTickProvider: (() -> Double?)? = nil,
        layoutService: any GrandStaffNotationLayoutServiceProtocol = GrandStaffNotationLayoutService(),
        viewportLayoutService: any GrandStaffNotationViewportLayoutServiceProtocol = GrandStaffNotationViewportLayoutService()
    ) {
        self.guides = guides
        self.currentGuide = currentGuide
        self.measureSpans = measureSpans
        self.context = context
        self.scrollTickProvider = scrollTickProvider
        self.layoutService = layoutService
        self.viewportLayoutService = viewportLayoutService
    }

    var body: some View {
        // KEEP_GEOMETRYREADER: needs exact viewport size for notation layout + scroll anchoring.
        GeometryReader { proxy in
            let lineSpacing = fixedLineSpacing
            let contentWidth = resolvedContentWidth(for: proxy.size, lineSpacing: lineSpacing)
            let halfWindowTicks = resolvedHalfWindowTicks(contentWidth: contentWidth, lineSpacing: lineSpacing)
            let staffStepBounds = resolvedStaffStepBounds(guides: guides)

            let layout = layoutService.makeLayout(
                guides: guides,
                currentGuide: currentGuide,
                measureSpans: measureSpans,
                context: context,
                halfWindowTicks: halfWindowTicks,
                scrollTick: scrollTickProvider?() ?? nil
            )

            let viewLayout = viewportLayoutService.makeLayout(
                size: proxy.size,
                lineSpacing: lineSpacing,
                items: layout.items,
                chords: layout.chords,
                beams: layout.beams,
                context: layout.context,
                staffStepBounds: staffStepBounds
            )
            let chordsByID = Dictionary(uniqueKeysWithValues: layout.chords.map { ($0.id, $0) })
            let itemsByChordID = Dictionary(grouping: layout.items, by: { $0.chordID ?? "" })
            let defaultScrollAnchorY = resolvedDefaultScrollAnchorY(layout: viewLayout)

            ScrollViewReader { scrollProxy in
                ScrollView(.vertical) {
                    ZStack(alignment: .topLeading) {
                        Canvas { context, _ in
                            context.translateBy(x: 0, y: alignedToPixel(viewLayout.canvasYOffset))
                            drawGrandStaffLines(in: context, layout: viewLayout)
                            drawContext(in: context, layout: viewLayout)
                            drawBarlines(layout.barlines, in: context, layout: viewLayout)
                            drawBeams(
                                layout.beams,
                                chordsByID: chordsByID,
                                itemsByChordID: itemsByChordID,
                                in: context,
                                layout: viewLayout
                            )
                            drawStems(
                                layout.chords,
                                beamedChordIDs: Set(layout.beams.flatMap(\.chordIDs)),
                                itemsByChordID: itemsByChordID,
                                in: context,
                                layout: viewLayout
                            )
                            drawItems(layout.items, in: context, layout: viewLayout)
                        }
                        .frame(width: proxy.size.width, height: viewLayout.requiredHeight)

                        VStack(spacing: 0) {
                            Color.clear.frame(height: defaultScrollAnchorY)
                            Color.clear
                                .frame(width: 1, height: 1)
                                .id(DefaultScrollAnchorID.value)
                            Spacer(minLength: 0)
                        }
                        .frame(width: 1, height: viewLayout.requiredHeight, alignment: .top)
                    }
                }
                .scrollIndicators(.hidden)
                .onAppear {
                    centerIfNeeded(firstGuideID: guides.first?.id, scrollProxy: scrollProxy)
                }
                .onChange(of: guides.first?.id) {
                    centerIfNeeded(firstGuideID: guides.first?.id, scrollProxy: scrollProxy)
                }
            }
        }
        .accessibilityLabel("Grand Staff 五线谱")
    }

    private enum DefaultScrollAnchorID {
        static let value = "grandstaff-default-anchor"
    }

    private func resolvedDefaultScrollAnchorY(
        layout: GrandStaffNotationViewportLayoutService.Layout
    ) -> CGFloat {
        let trebleTop = layout.trebleTopLineY + layout.canvasYOffset
        let bassBottom = layout.bassBottomLineY + layout.canvasYOffset
        let center = (trebleTop + bassBottom) / 2
        return min(max(0, center), layout.requiredHeight)
    }

    private func centerIfNeeded(firstGuideID: Int?, scrollProxy: ScrollViewProxy) {
        guard centeredForFirstGuideID != firstGuideID else { return }
        centeredForFirstGuideID = firstGuideID
        Task { @MainActor in
            await Task.yield()
            scrollProxy.scrollTo(DefaultScrollAnchorID.value, anchor: .center)
        }
    }

    private func drawGrandStaffLines(
        in context: GraphicsContext,
        layout: GrandStaffNotationViewportLayoutService.Layout
    ) {
        let lineColor = Color.primary.opacity(0.22)
        let stroke = StrokeStyle(lineWidth: 1.0)

        func drawStaff(topLineY: CGFloat) {
            for i in 0 ..< 5 {
                let y = alignedToPixel(topLineY + CGFloat(i) * layout.lineSpacing)
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: alignedToPixel(layout.size.width), y: y))
                context.stroke(path, with: .color(lineColor), style: stroke)
            }
        }

        drawStaff(topLineY: layout.trebleTopLineY)
        drawStaff(topLineY: layout.bassTopLineY)
    }

    private func drawContext(in context: GraphicsContext, layout: GrandStaffNotationViewportLayoutService.Layout) {
        guard let staffContext = layout.context else { return }

        let trebleKeyCenterY = layout.yPosition(staffStep: 4, staffNumber: 1)
        let bassKeyCenterY = layout.yPosition(staffStep: 4, staffNumber: 2)
        let trebleClefFont = Font.custom("Bravura", size: layout.trebleClefFontSize)
        let bassClefFont = Font.custom("Bravura", size: layout.bassClefFontSize)
        let keySignatureFont = Font.custom("Bravura", size: layout.keySignatureFontSize)
        let timeSignatureFont = Font.custom("Bravura", size: layout.timeSignatureFontSize)

        context.draw(
            Text(staffContext.trebleClefSymbol).font(trebleClefFont),
            at: CGPoint(x: layout.contextMinX + layout.lineSpacing * 0.6, y: layout.trebleClefY),
            anchor: .leading
        )
        context.draw(
            Text(staffContext.bassClefSymbol).font(bassClefFont),
            at: CGPoint(x: layout.contextMinX + layout.lineSpacing * 0.6, y: layout.bassClefY),
            anchor: .leading
        )

        // Key signature and time signature are drawn on both staves for grand staff.
        let keyMinX = layout.contextMinX + layout.lineSpacing * 3.1
        let timeMinXBase = layout.contextMinX + layout.lineSpacing * 5.8

        if let fifths = staffContext.keySignatureFifths, fifths != 0 {
            let keyAdvanceTreble = drawKeySignature(
                fifths: fifths,
                staffNumber: 1,
                xStart: keyMinX,
                font: keySignatureFont,
                in: context,
                layout: layout
            )
            _ = drawKeySignature(
                fifths: fifths,
                staffNumber: 2,
                xStart: keyMinX,
                font: keySignatureFont,
                in: context,
                layout: layout
            )

            let timeMinX = max(timeMinXBase, keyMinX + keyAdvanceTreble + layout.lineSpacing * 0.8)
            drawTimeSignature(
                text: staffContext.timeSignatureText,
                staffNumber: 1,
                xStart: timeMinX,
                centerY: trebleKeyCenterY,
                font: timeSignatureFont,
                in: context,
                layout: layout
            )
            drawTimeSignature(
                text: staffContext.timeSignatureText,
                staffNumber: 2,
                xStart: timeMinX,
                centerY: bassKeyCenterY,
                font: timeSignatureFont,
                in: context,
                layout: layout
            )
        } else {
            drawTimeSignature(
                text: staffContext.timeSignatureText,
                staffNumber: 1,
                xStart: timeMinXBase,
                centerY: trebleKeyCenterY,
                font: timeSignatureFont,
                in: context,
                layout: layout
            )
            drawTimeSignature(
                text: staffContext.timeSignatureText,
                staffNumber: 2,
                xStart: timeMinXBase,
                centerY: bassKeyCenterY,
                font: timeSignatureFont,
                in: context,
                layout: layout
            )
        }
    }

    private func drawKeySignature(
        fifths: Int,
        staffNumber: Int,
        xStart: CGFloat,
        font: Font,
        in context: GraphicsContext,
        layout: GrandStaffNotationViewportLayoutService.Layout
    ) -> CGFloat {
        let clamped = max(-7, min(7, fifths))
        guard clamped != 0 else { return 0 }

        let stepsTrebleSharps: [Int] = [8, 5, 2, 6, 3, 7, 4]
        let stepsTrebleFlats: [Int] = [4, 7, 3, 6, 2, 5, 8]

        // Bass clef is shifted down by a fifth relative to treble for key signature placement.
        // Using common engraving placements: sharps -> [6, 3, 7, 4, 8, 5, 9], flats -> [2, 5, 1, 4, 0, 3, -1]
        let stepsBassSharps: [Int] = [6, 3, 7, 4, 8, 5, 9]
        let stepsBassFlats: [Int] = [2, 5, 1, 4, 0, 3, -1]

        let isSharp = clamped > 0
        let count = abs(clamped)
        let glyph = isSharp ? "\u{E262}" : "\u{E260}"

        let steps: [Int] = if staffNumber >= 2 {
            isSharp ? stepsBassSharps : stepsBassFlats
        } else {
            isSharp ? stepsTrebleSharps : stepsTrebleFlats
        }

        let xStride = layout.lineSpacing * 0.78
        for i in 0 ..< min(count, steps.count) {
            let y = layout.yPosition(staffStep: steps[i], staffNumber: staffNumber)
            context.draw(
                Text(glyph).font(font),
                at: CGPoint(x: xStart + CGFloat(i) * xStride, y: y),
                anchor: .leading
            )
        }
        return CGFloat(min(count, steps.count)) * xStride
    }

    private func drawTimeSignature(
        text: String?,
        staffNumber _: Int,
        xStart: CGFloat,
        centerY: CGFloat,
        font: Font,
        in context: GraphicsContext,
        layout: GrandStaffNotationViewportLayoutService.Layout
    ) {
        guard let text, text.isEmpty == false else { return }

        // Prefer professional, stacked SMuFL time signature digits.
        // Supports common forms like "4/4", "3/4", "6/8". Falls back to raw text.
        let parts = text.split(separator: "/")
        guard parts.count == 2, let top = Int(parts[0]), let bottom = Int(parts[1]) else {
            context.draw(Text(text).font(font), at: CGPoint(x: xStart, y: centerY), anchor: .leading)
            return
        }

        func digitGlyph(_ digit: Int) -> String? {
            guard (0 ... 9).contains(digit) else { return nil }
            let scalar = UnicodeScalar(0xE080 + digit)!
            return String(scalar)
        }

        func glyphString(for number: Int) -> String? {
            let digits = String(number).compactMap { Int(String($0)) }
            guard digits.isEmpty == false else { return nil }
            let glyphs = digits.compactMap(digitGlyph)
            guard glyphs.count == digits.count else { return nil }
            return glyphs.joined()
        }

        guard let topGlyphs = glyphString(for: top), let bottomGlyphs = glyphString(for: bottom) else {
            context.draw(Text(text).font(font), at: CGPoint(x: xStart, y: centerY), anchor: .leading)
            return
        }

        let vOffset = layout.lineSpacing * 0.78
        context.draw(Text(topGlyphs).font(font), at: CGPoint(x: xStart, y: centerY - vOffset), anchor: .leading)
        context.draw(Text(bottomGlyphs).font(font), at: CGPoint(x: xStart, y: centerY + vOffset), anchor: .leading)
    }

    private func drawBarlines(
        _ barlines: [GrandStaffNotationBarline],
        in context: GraphicsContext,
        layout: GrandStaffNotationViewportLayoutService.Layout
    ) {
        guard barlines.isEmpty == false else { return }

        let stroke = StrokeStyle(lineWidth: 1.2)
        let topY = layout.trebleTopLineY
        let bottomY = layout.bassBottomLineY

        for barline in barlines {
            let x = alignedToPixel(layout.xPosition(barline.xPosition))
            var path = Path()
            path.move(to: CGPoint(x: x, y: alignedToPixel(topY)))
            path.addLine(to: CGPoint(x: x, y: alignedToPixel(bottomY)))
            context.stroke(path, with: .color(Color.primary.opacity(0.25)), style: stroke)
        }
    }

    private func drawItems(
        _ items: [GrandStaffNotationItem],
        in context: GraphicsContext,
        layout: GrandStaffNotationViewportLayoutService.Layout
    ) {
        guard items.isEmpty == false else { return }

        for item in items {
            let x = layout.xPosition(item.xPosition) + CGFloat(item.noteHeadXOffset) * layout.noteWidth
            let y = layout.yPosition(staffStep: item.staffStep, staffNumber: item.staffNumber)
            drawNoteHead(item: item, x: x, y: y, in: context, layout: layout)

            let ledgerSteps = layoutService.ledgerStaffSteps(for: item.staffStep)
            for step in ledgerSteps {
                let ledgerY = alignedToPixel(layout.yPosition(staffStep: step, staffNumber: item.staffNumber))
                var path = Path()
                path.move(to: CGPoint(x: x - layout.noteWidth * 0.65, y: ledgerY))
                path.addLine(to: CGPoint(x: x + layout.noteWidth * 0.65, y: ledgerY))
                context.stroke(path, with: .color(Color.primary.opacity(0.22)), style: .init(lineWidth: 1))
            }
        }
    }

    private func alignedToPixel(_ value: CGFloat) -> CGFloat {
        guard displayScale.isFinite, displayScale > 0 else { return value }
        return (value * displayScale).rounded() / displayScale
    }

    private func resolvedContentWidth(for size: CGSize, lineSpacing: CGFloat) -> CGFloat {
        let contextMinX: CGFloat = 4
        let contextWidth: CGFloat = lineSpacing * 7.0
        let contentMinX = contextMinX + contextWidth
        let contentMaxX = min(size.width - 18, size.width * 0.96)
        return max(1, contentMaxX - contentMinX)
    }

    private func resolvedHalfWindowTicks(contentWidth: CGFloat, lineSpacing: CGFloat) -> Int {
        // Keep horizontal density stable: don't stretch/compress music when the window resizes.
        // Wider window => show more ticks (more measures), instead of spreading notes out.
        let pointsPerQuarter = max(1, lineSpacing * 6.0)
        let ticksPerPoint = Double(MusicXMLTempoMap.ticksPerQuarter) / Double(pointsPerQuarter)
        let half = Int((Double(contentWidth) * ticksPerPoint) / 2.0)
        return max(MusicXMLTempoMap.ticksPerQuarter, half)
    }

    private func resolvedStaffStepBounds(
        guides: [PianoHighlightGuide]
    ) -> GrandStaffNotationViewportLayoutService.StaffStepBounds {
        guard guides.isEmpty == false else { return .default }

        var minTrebleStep = 0
        var maxTrebleStep = 8
        var minBassStep = 0
        var maxBassStep = 8

        for guide in guides {
            for note in guide.activeNotes + guide.triggeredNotes {
                let staffNumber = resolvedStaffNumber(note.staff)
                let step = layoutService.staffStep(for: note.midiNote, staffNumber: staffNumber)
                if staffNumber >= 2 {
                    minBassStep = min(minBassStep, step)
                    maxBassStep = max(maxBassStep, step)
                } else {
                    minTrebleStep = min(minTrebleStep, step)
                    maxTrebleStep = max(maxTrebleStep, step)
                }
            }
        }

        return GrandStaffNotationViewportLayoutService.StaffStepBounds(
            minTrebleStep: minTrebleStep,
            maxTrebleStep: maxTrebleStep,
            minBassStep: minBassStep,
            maxBassStep: maxBassStep
        )
    }

    private func resolvedStaffNumber(_ staff: Int?) -> Int {
        guard let staff else { return 1 }
        return (staff >= 2) ? 2 : 1
    }

}

#Preview("Grand Staff") {
    GrandStaffNotationView(
        guides: [],
        currentGuide: nil,
        measureSpans: [],
        context: GrandStaffNotationContext()
    )
    .frame(width: 800, height: 300)
    .padding()
}
