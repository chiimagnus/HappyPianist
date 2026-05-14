import SwiftUI

struct GrandStaffNotationView: View {
    let guides: [PianoHighlightGuide]
    let currentGuide: PianoHighlightGuide?
    let measureSpans: [MusicXMLMeasureSpan]
    let context: GrandStaffNotationContext?
    var scrollTickProvider: (() -> Double?)?

    private let layoutService = GrandStaffNotationLayoutService()

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
                let viewLayout = GrandStaffViewLayout(size: size, context: layout.context)
                drawGrandStaffLines(in: context, layout: viewLayout)
                drawContext(in: context, layout: viewLayout)
                drawBarlines(layout.barlines, in: context, layout: viewLayout)
                drawItems(layout.items, in: context, layout: viewLayout)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityLabel("Grand Staff 五线谱")
    }

    private func drawGrandStaffLines(in context: GraphicsContext, layout: GrandStaffViewLayout) {
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

    private func drawContext(in context: GraphicsContext, layout: GrandStaffViewLayout) {
        guard let staffContext = layout.context else { return }

        let trebleCenterY = layout.yPosition(staffStep: 4, staffNumber: 1)
        let bassCenterY = layout.yPosition(staffStep: 4, staffNumber: 2)

        context.draw(
            Text(staffContext.trebleClefSymbol).font(.system(size: layout.lineSpacing * 2.2)),
            at: CGPoint(x: layout.contextMinX + layout.lineSpacing * 1.0, y: trebleCenterY)
        )
        context.draw(
            Text(staffContext.bassClefSymbol).font(.system(size: layout.lineSpacing * 2.0)),
            at: CGPoint(x: layout.contextMinX + layout.lineSpacing * 1.0, y: bassCenterY)
        )

        if let keySignatureText = staffContext.keySignatureText, keySignatureText.isEmpty == false {
            context.draw(
                Text(keySignatureText).font(.system(size: layout.lineSpacing * 1.2)),
                at: CGPoint(x: layout.contextMinX + layout.lineSpacing * 3.2, y: trebleCenterY)
            )
        }

        if let timeSignatureText = staffContext.timeSignatureText, timeSignatureText.isEmpty == false {
            context.draw(
                Text(timeSignatureText).font(.system(size: layout.lineSpacing * 1.2, weight: .semibold)),
                at: CGPoint(x: layout.contextMinX + layout.lineSpacing * 5.6, y: trebleCenterY)
            )
        }
    }

    private func drawBarlines(
        _ barlines: [GrandStaffNotationBarline],
        in context: GraphicsContext,
        layout: GrandStaffViewLayout
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
        layout: GrandStaffViewLayout
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
        layout: GrandStaffViewLayout
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

private struct GrandStaffViewLayout {
    let size: CGSize
    let context: GrandStaffNotationContext?

    init(size: CGSize, context: GrandStaffNotationContext?) {
        self.size = size
        self.context = context
    }

    var lineSpacing: CGFloat {
        max(10, min(18, size.height * 0.085))
    }

    var noteWidth: CGFloat {
        lineSpacing * 1.05
    }

    var noteHeight: CGFloat {
        lineSpacing * 0.70
    }

    var contextMinX: CGFloat {
        4
    }

    var contextWidth: CGFloat {
        lineSpacing * 7.0
    }

    var contentMinX: CGFloat {
        contextMinX + contextWidth
    }

    var contentMaxX: CGFloat {
        min(size.width - 18, size.width * 0.96)
    }

    var trebleTopLineY: CGFloat {
        size.height * 0.10
    }

    var trebleBottomLineY: CGFloat {
        trebleTopLineY + lineSpacing * 4
    }

    var bassTopLineY: CGFloat {
        trebleBottomLineY + lineSpacing * 2.8
    }

    var bassBottomLineY: CGFloat {
        bassTopLineY + lineSpacing * 4
    }

    func xPosition(_ normalized: Double) -> CGFloat {
        let clamped = max(-0.2, min(1.2, normalized))
        return contentMinX + CGFloat(clamped) * (contentMaxX - contentMinX)
    }

    func yPosition(staffStep: Int, staffNumber: Int) -> CGFloat {
        let bottomLineY = (staffNumber >= 2) ? bassBottomLineY : trebleBottomLineY
        return bottomLineY - CGFloat(staffStep) * lineSpacing / 2
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
