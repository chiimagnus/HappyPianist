import SwiftUI

struct GrandStaffNotationView: View {
    let guides: [PianoHighlightGuide]
    let currentGuide: PianoHighlightGuide?
    let measureSpans: [MusicXMLMeasureSpan]
    let context: GrandStaffNotationContext?
    var scrollTickProvider: (() -> Double)?

    private let layoutService = GrandStaffNotationLayoutService()

    var body: some View {
        GeometryReader { proxy in
            let layout = layoutService.makeLayout(
                guides: guides,
                currentGuide: currentGuide,
                measureSpans: measureSpans,
                context: context,
                scrollTick: scrollTickProvider?()
            )

            Canvas { context, size in
                drawGrandStaffLines(in: context, size: size)

                let placeholder = Text("Grand Staff (WIP)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                context.draw(placeholder, at: CGPoint(x: size.width / 2, y: size.height / 2))

                let stats = Text("items \(layout.items.count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                context.draw(stats, at: CGPoint(x: 60, y: size.height - 16))
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityLabel("Grand Staff 五线谱")
    }

    private func drawGrandStaffLines(in context: GraphicsContext, size: CGSize) {
        let lineColor = Color.primary.opacity(0.22)
        let stroke = StrokeStyle(lineWidth: 1.0)

        let gapBetweenStaves = size.height * 0.16
        let staffHeight = (size.height - gapBetweenStaves) / 2
        let lineSpacing = staffHeight / 6

        let trebleTopY = size.height * 0.08
        let bassTopY = trebleTopY + staffHeight + gapBetweenStaves

        func drawStaff(atTopY topY: CGFloat) {
            for i in 0..<5 {
                let y = topY + CGFloat(i) * lineSpacing
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(lineColor), style: stroke)
            }
        }

        drawStaff(atTopY: trebleTopY)
        drawStaff(atTopY: bassTopY)
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

