import SwiftUI

struct GrandStaffNotationView: View {
    let guides: [PianoHighlightGuide]
    let currentGuide: PianoHighlightGuide?
    let measureSpans: [MusicXMLMeasureSpan]
    let context: GrandStaffNotationContext?
    var scrollTickProvider: (() -> Double?)?

    private let layoutService = GrandStaffNotationLayoutService()
    private let viewportLayoutService = GrandStaffNotationViewportLayoutService()

    var body: some View {
        GeometryReader { proxy in
            let layout = layoutService.makeLayout(
                guides: guides,
                currentGuide: currentGuide,
                measureSpans: measureSpans,
                context: context,
                scrollTick: scrollTickProvider?() ?? nil
            )

            Canvas { context, size in
                let viewLayout = viewportLayoutService.makeLayout(
                    size: size,
                    items: layout.items,
                    context: layout.context
                )
                drawGrandStaffLines(in: context, layout: viewLayout)
                drawContext(in: context, layout: viewLayout)
                drawBarlines(layout.barlines, in: context, layout: viewLayout)
                drawItems(layout.items, in: context, layout: viewLayout)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityLabel("Grand Staff 五线谱")
    }

    private func drawGrandStaffLines(in context: GraphicsContext, layout: GrandStaffNotationViewportLayoutService.Layout) {
        let lineColor = Color.primary.opacity(0.22)
        let stroke = StrokeStyle(lineWidth: 1.0)

        func drawStaff(topLineY: CGFloat) {
            for i in 0..<5 {
                let y = topLineY + CGFloat(i) * layout.lineSpacing
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: layout.size.width, y: y))
                context.stroke(path, with: .color(lineColor), style: stroke)
            }
        }

        drawStaff(topLineY: layout.trebleTopLineY)
        drawStaff(topLineY: layout.bassTopLineY)
    }

    private func drawContext(in context: GraphicsContext, layout: GrandStaffNotationViewportLayoutService.Layout) {
        guard let staffContext = layout.context else { return }

        let trebleKeyCenterY = layout.yPosition(staffStep: 4, staffNumber: 1)

        context.draw(
            Text(staffContext.trebleClefSymbol).font(.system(size: layout.trebleClefFontSize)),
            at: CGPoint(x: layout.contextMinX + layout.lineSpacing * 1.0, y: layout.trebleClefY)
        )
        context.draw(
            Text(staffContext.bassClefSymbol).font(.system(size: layout.bassClefFontSize)),
            at: CGPoint(x: layout.contextMinX + layout.lineSpacing * 1.0, y: layout.bassClefY)
        )

        if let keySignatureText = staffContext.keySignatureText, keySignatureText.isEmpty == false {
            context.draw(
                Text(keySignatureText).font(.system(size: layout.keySignatureFontSize)),
                at: CGPoint(x: layout.contextMinX + layout.lineSpacing * 3.2, y: trebleKeyCenterY)
            )
        }

        if let timeSignatureText = staffContext.timeSignatureText, timeSignatureText.isEmpty == false {
            context.draw(
                Text(timeSignatureText).font(.system(size: layout.timeSignatureFontSize, weight: .semibold)),
                at: CGPoint(x: layout.contextMinX + layout.lineSpacing * 5.6, y: trebleKeyCenterY)
            )
        }
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
            let x = layout.xPosition(barline.xPosition)
            var path = Path()
            path.move(to: CGPoint(x: x, y: topY))
            path.addLine(to: CGPoint(x: x, y: bottomY))
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
                let ledgerY = layout.yPosition(staffStep: step, staffNumber: item.staffNumber)
                var path = Path()
                path.move(to: CGPoint(x: x - layout.noteWidth * 0.65, y: ledgerY))
                path.addLine(to: CGPoint(x: x + layout.noteWidth * 0.65, y: ledgerY))
                context.stroke(path, with: .color(Color.primary.opacity(0.22)), style: .init(lineWidth: 1))
            }
        }
    }

    private func drawNoteHead(
        item: GrandStaffNotationItem,
        x: CGFloat,
        y: CGFloat,
        in context: GraphicsContext,
        layout: GrandStaffNotationViewportLayoutService.Layout
    ) {
        let rect = CGRect(
            x: x - layout.noteWidth / 2,
            y: y - layout.noteHeight / 2,
            width: layout.noteWidth,
            height: layout.noteHeight
        )

        let path = Path(ellipseIn: rect)

        let fillColor: Color = item.isHighlighted ? .primary : .primary.opacity(0.55)
        context.fill(path, with: .color(fillColor))

        if item.showsSharpAccidental {
            let accidental = Text("♯").font(.system(size: layout.lineSpacing * 1.0))
            context.draw(accidental, at: CGPoint(x: x - layout.noteWidth * 1.0, y: y))
        }
    }
}

#Preview("Grand Staff") {
    GrandStaffNotationView(
        guides: [],
        currentGuide: nil,
        measureSpans: [],
        context: GrandStaffNotationContext()
    )
    .frame(width: 800, height: 180)
    .padding()
}
