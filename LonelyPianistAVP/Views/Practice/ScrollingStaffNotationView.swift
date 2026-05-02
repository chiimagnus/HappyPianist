import SwiftUI

struct ScrollingStaffNotationView: View {
    let guides: [PianoHighlightGuide]
    let currentGuide: PianoHighlightGuide?
    let measureSpans: [MusicXMLMeasureSpan]
    let notationContext: ScrollingStaffNotationContext?
    let halfWindowTicks: Int

    private let layoutService = ScrollingStaffNotationLayoutService()

    init(
        guides: [PianoHighlightGuide],
        currentGuide: PianoHighlightGuide?,
        measureSpans: [MusicXMLMeasureSpan] = [],
        context: ScrollingStaffNotationContext? = nil,
        halfWindowTicks: Int = 1_920
    ) {
        self.guides = guides
        self.currentGuide = currentGuide
        self.measureSpans = measureSpans
        notationContext = context
        self.halfWindowTicks = halfWindowTicks
    }

    var body: some View {
        Canvas { context, size in
            let layoutData = notationLayout
            let ctx = layoutData.context ?? ScrollingStaffNotationContext()
            let layout = StaffCanvasLayout(size: size, notationContext: ctx)

            drawStaff(in: &context, layout: layout)
            drawContext(ctx, in: &context, layout: layout)

            let clipRect = CGRect(
                x: layout.contentMinX,
                y: 0,
                width: layout.size.width - layout.contentMinX,
                height: layout.size.height
            )
            context.clip(to: Path(clipRect))

            for rest in layoutData.rests {
                drawRest(rest, in: &context, layout: layout)
            }

            for item in layoutData.items {
                drawTie(for: item, in: &context, layout: layout)
            }

            for item in layoutData.items {
                drawLedgerLines(for: item, in: &context, layout: layout)
            }

            let itemByID = Dictionary(uniqueKeysWithValues: layoutData.items.map { ($0.id, $0) })
            let chordByID = Dictionary(uniqueKeysWithValues: layoutData.chords.map { ($0.id, $0) })
            for chord in layoutData.chords {
                drawStem(for: chord, itemByID: itemByID, in: &context, layout: layout)
            }
            for beam in layoutData.beams {
                drawBeam(beam, chordByID: chordByID, itemByID: itemByID, in: &context, layout: layout)
            }

            for item in layoutData.items {
                drawNoteHead(item, in: &context, layout: layout)
            }
        }
        .overlay(alignment: .topLeading) {
            Text("五线谱")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .overlay {
            if notationLayout.items.isEmpty && notationLayout.rests.isEmpty {
                Text("导入曲谱后显示滚动五线谱")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .background(.white)
        .clipShape(.rect(cornerRadius: 16))
    }

    private var notationLayout: ScrollingStaffNotationLayout {
        layoutService.makeLayout(
            guides: guides,
            currentGuide: currentGuide,
            measureSpans: measureSpans,
            context: notationContext,
            halfWindowTicks: halfWindowTicks
        )
    }

    private func drawStaff(in context: inout GraphicsContext, layout: StaffCanvasLayout) {
        let staffPath = Path { path in
            for index in 0 ..< 5 {
                let y = layout.topLineY + CGFloat(index) * layout.lineSpacing
                path.move(to: CGPoint(x: 4, y: y))
                path.addLine(to: CGPoint(x: layout.size.width - 4, y: y))
            }
        }
        context.stroke(staffPath, with: .color(.black.opacity(0.65)), lineWidth: 0.9)
    }

    private func drawContext(
        _ notationContext: ScrollingStaffNotationContext,
        in context: inout GraphicsContext,
        layout: StaffCanvasLayout
    ) {
        let centerY = (layout.topLineY + layout.bottomLineY) / 2
        let clefX = 4 + layout.lineSpacing * 1.0

        context.draw(
            Text(notationContext.clefSymbol)
                .font(.system(size: layout.lineSpacing * 3.5, weight: .regular))
                .foregroundStyle(.black.opacity(0.85)),
            at: CGPoint(x: clefX, y: centerY + layout.lineSpacing * 0.15),
            anchor: .center
        )

        var textX = clefX + layout.lineSpacing * 2.0
        if let fifths = notationContext.keySignatureFifths, fifths != 0 {
            let isSharp = fifths > 0
            let count = min(abs(fifths), 7)
            let trebleSharpSteps: [Int] = [8, 5, 2, 6, 3, 7, 4]
            let trebleFlatSteps: [Int] = [4, 7, 3, 6, 2, 5, 8]
            let steps = isSharp ? trebleSharpSteps : trebleFlatSteps
            let symbol = isSharp ? "♯" : "♭"
            for i in 0 ..< count {
                let step = steps[i]
                let y = layout.yPosition(staffStep: step)
                context.draw(
                    Text(symbol)
                        .font(.system(size: layout.lineSpacing * 1.15, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.8)),
                    at: CGPoint(x: textX, y: y),
                    anchor: .center
                )
                textX += layout.lineSpacing * 0.55
            }
        } else if let keySignatureText = notationContext.keySignatureText, keySignatureText.isEmpty == false {
            context.draw(
                Text(keySignatureText)
                    .font(.system(size: layout.lineSpacing * 1.15, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.8)),
                at: CGPoint(x: textX, y: centerY - layout.lineSpacing * 0.03),
                anchor: .center
            )
            textX += max(layout.lineSpacing * 1.2, CGFloat(keySignatureText.count) * layout.lineSpacing * 0.46)
        }

        if let timeSignatureText = notationContext.timeSignatureText, timeSignatureText.isEmpty == false {
            let parts = timeSignatureText.split(separator: "/", omittingEmptySubsequences: false)
            if parts.count == 2 {
                let topY = centerY - layout.lineSpacing * 0.95
                let bottomY = centerY + layout.lineSpacing * 0.95
                context.draw(
                    Text(String(parts[0]))
                        .font(.system(size: layout.lineSpacing * 1.0, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.black.opacity(0.82)),
                    at: CGPoint(x: textX + layout.lineSpacing * 0.35, y: topY),
                    anchor: .center
                )
                context.draw(
                    Text(String(parts[1]))
                        .font(.system(size: layout.lineSpacing * 1.0, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.black.opacity(0.82)),
                    at: CGPoint(x: textX + layout.lineSpacing * 0.35, y: bottomY),
                    anchor: .center
                )
            }
        }
    }

    private func drawRest(
        _ rest: ScrollingStaffNotationRest,
        in context: inout GraphicsContext,
        layout: StaffCanvasLayout
    ) {
        let center = CGPoint(
            x: layout.xPosition(rest.xPosition),
            y: layout.yPosition(staffStep: 4)
        )
        let color = Color.black.opacity(rest.isHighlighted ? 0.85 : 0.55)

        switch rest.noteValue {
            case .whole:
                let rect = CGRect(
                    x: center.x - layout.noteWidth * 0.45,
                    y: layout.yPosition(staffStep: 6),
                    width: layout.noteWidth * 0.9,
                    height: layout.lineSpacing * 0.35
                )
                context.fill(Path(rect), with: .color(color))
            case .half:
                let rect = CGRect(
                    x: center.x - layout.noteWidth * 0.45,
                    y: layout.yPosition(staffStep: 4) - layout.lineSpacing * 0.35,
                    width: layout.noteWidth * 0.9,
                    height: layout.lineSpacing * 0.35
                )
                context.fill(Path(rect), with: .color(color))
            case .quarter:
                let path = Path { path in
                    path.move(to: CGPoint(x: center.x + layout.noteWidth * 0.2, y: center.y - layout.lineSpacing * 1.35))
                    path.addCurve(
                        to: CGPoint(x: center.x - layout.noteWidth * 0.1, y: center.y - layout.lineSpacing * 0.15),
                        control1: CGPoint(x: center.x - layout.noteWidth * 0.55, y: center.y - layout.lineSpacing * 0.95),
                        control2: CGPoint(x: center.x + layout.noteWidth * 0.42, y: center.y - layout.lineSpacing * 0.58)
                    )
                    path.addCurve(
                        to: CGPoint(x: center.x + layout.noteWidth * 0.08, y: center.y + layout.lineSpacing * 1.12),
                        control1: CGPoint(x: center.x - layout.noteWidth * 0.58, y: center.y + layout.lineSpacing * 0.2),
                        control2: CGPoint(x: center.x + layout.noteWidth * 0.34, y: center.y + layout.lineSpacing * 0.52)
                    )
                }
                context.stroke(path, with: .color(color), lineWidth: max(1.4, layout.lineSpacing * 0.17))
            case .eighth, .sixteenth, .thirtySecond:
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: center.x - layout.noteWidth * 0.25,
                        y: center.y - layout.lineSpacing * 0.95,
                        width: layout.noteWidth * 0.42,
                        height: layout.noteWidth * 0.42
                    )),
                    with: .color(color)
                )
                let path = Path { path in
                    path.move(to: CGPoint(x: center.x + layout.noteWidth * 0.08, y: center.y - layout.lineSpacing * 0.7))
                    path.addLine(to: CGPoint(x: center.x - layout.noteWidth * 0.34, y: center.y + layout.lineSpacing * 0.92))
                }
                context.stroke(path, with: .color(color), lineWidth: max(1.2, layout.lineSpacing * 0.13))
        }
    }

    private func drawLedgerLines(
        for item: ScrollingStaffNotationItem,
        in context: inout GraphicsContext,
        layout: StaffCanvasLayout
    ) {
        let x = noteHeadCenter(for: item, layout: layout).x
        let noteWidth = layout.noteWidth
        let ledgerSteps = layoutService.ledgerStaffSteps(for: item.staffStep)
        guard ledgerSteps.isEmpty == false else { return }
        let path = Path { path in
            for step in ledgerSteps {
                let y = layout.yPosition(staffStep: step)
                path.move(to: CGPoint(x: x - noteWidth * 0.75, y: y))
                path.addLine(to: CGPoint(x: x + noteWidth * 0.75, y: y))
            }
        }
        context.stroke(path, with: .color(.black.opacity(0.65)), lineWidth: 1.4)
    }

    private func drawNoteHead(
        _ item: ScrollingStaffNotationItem,
        in context: inout GraphicsContext,
        layout: StaffCanvasLayout
    ) {
        let center = noteHeadCenter(for: item, layout: layout)
        let x = center.x
        let y = center.y
        let rect = CGRect(
            x: x - layout.noteWidth / 2,
            y: y - layout.noteHeight / 2,
            width: layout.noteWidth,
            height: layout.noteHeight
        )

        let fillColor = item.isHighlighted ? Color.yellow.opacity(0.70) : Color.black.opacity(0.88)
        let strokeColor = item.isHighlighted ? Color.red.opacity(0.60) : Color.black.opacity(0.25)

        let noteHead = Path(ellipseIn: rect)
        if item.usesOpenNoteHead {
            context.drawLayer { layerContext in
                var gc = layerContext
                gc.translateBy(x: center.x, y: center.y)
                gc.rotate(by: .degrees(-12))
                gc.translateBy(x: -center.x, y: -center.y)
                gc.fill(noteHead, with: .color(.white))
                gc.stroke(noteHead, with: .color(fillColor), lineWidth: item.isHighlighted ? 2.8 : 1.8)
            }
        } else {
            context.drawLayer { layerContext in
                var gc = layerContext
                gc.translateBy(x: center.x, y: center.y)
                gc.rotate(by: .degrees(-12))
                gc.translateBy(x: -center.x, y: -center.y)
                gc.fill(noteHead, with: .color(fillColor))
                gc.stroke(noteHead, with: .color(strokeColor), lineWidth: item.isHighlighted ? 2.8 : 1.0)
            }
        }

        if item.showsSharpAccidental {
            drawSharpAccidental(at: CGPoint(x: x - layout.noteWidth * 0.85, y: y), in: &context, layout: layout)
        }
        if item.dotCount > 0 {
            drawDots(count: item.dotCount, staffStep: item.staffStep, noteX: x, in: &context, layout: layout)
        }
        if item.arpeggiate != nil {
            drawArpeggiate(at: CGPoint(x: x - layout.noteWidth * 1.45, y: y), in: &context, layout: layout)
        }
        drawArticulations(for: item, at: CGPoint(x: x, y: y), in: &context, layout: layout)
        drawFingering(for: item, at: CGPoint(x: x, y: y), in: &context, layout: layout)
        if item.isGrace {
            drawGraceSlash(for: item, at: CGPoint(x: x, y: y), in: &context, layout: layout)
        }
    }

    private func drawSharpAccidental(
        at center: CGPoint,
        in context: inout GraphicsContext,
        layout: StaffCanvasLayout
    ) {
        let height = layout.noteHeight * 1.3
        let width = layout.noteWidth * 0.44
        let path = Path { path in
            path.move(to: CGPoint(x: center.x - width * 0.25, y: center.y - height / 2))
            path.addLine(to: CGPoint(x: center.x - width * 0.25, y: center.y + height / 2))
            path.move(to: CGPoint(x: center.x + width * 0.25, y: center.y - height / 2))
            path.addLine(to: CGPoint(x: center.x + width * 0.25, y: center.y + height / 2))
            path.move(to: CGPoint(x: center.x - width / 2, y: center.y - height * 0.18))
            path.addLine(to: CGPoint(x: center.x + width / 2, y: center.y - height * 0.28))
            path.move(to: CGPoint(x: center.x - width / 2, y: center.y + height * 0.22))
            path.addLine(to: CGPoint(x: center.x + width / 2, y: center.y + height * 0.12))
        }
        context.stroke(path, with: .color(.black.opacity(0.8)), lineWidth: 1.1)
    }

    private func drawDots(
        count: Int,
        staffStep: Int,
        noteX: CGFloat,
        in context: inout GraphicsContext,
        layout: StaffCanvasLayout
    ) {
        let dotRadius = max(1.5, layout.lineSpacing * 0.12)
        let dotSpacing = layout.lineSpacing * 0.65
        let isOnLine = staffStep % 2 == 0
        let dotStaffStep = isOnLine ? staffStep + 1 : staffStep
        let dotY = layout.yPosition(staffStep: dotStaffStep)
        let startX = noteX + layout.noteWidth * 0.72

        for i in 0 ..< count {
            let dotCenter = CGPoint(x: startX + CGFloat(i) * dotSpacing, y: dotY)
            let dotRect = CGRect(
                x: dotCenter.x - dotRadius,
                y: dotCenter.y - dotRadius,
                width: dotRadius * 2,
                height: dotRadius * 2
            )
            context.fill(Path(ellipseIn: dotRect), with: .color(.black.opacity(0.82)))
        }
    }

    private func drawStem(
        for chord: ScrollingStaffNotationChord,
        itemByID: [String: ScrollingStaffNotationItem],
        in context: inout GraphicsContext,
        layout: StaffCanvasLayout
    ) {
        guard chord.noteValue != .whole else { return }
        guard let stem = stemGeometry(for: chord, itemByID: itemByID, layout: layout) else { return }
        let isBeamed = chord.itemIDs.contains { itemByID[$0]?.beamID != nil }

        if isBeamed {
            if stem.isGrace {
                let flagDirection: CGFloat = stem.direction == .up ? 1 : -1
                let flagPath = Path { path in
                    path.move(to: stem.end)
                    path.addCurve(
                        to: CGPoint(
                            x: stem.end.x + layout.noteWidth * 0.62,
                            y: stem.end.y + layout.lineSpacing * 0.72 * flagDirection
                        ),
                        control1: CGPoint(
                            x: stem.end.x + layout.noteWidth * 0.50,
                            y: stem.end.y + layout.lineSpacing * 0.10 * flagDirection
                        ),
                        control2: CGPoint(
                            x: stem.end.x + layout.noteWidth * 0.66,
                            y: stem.end.y + layout.lineSpacing * 0.44 * flagDirection
                        )
                    )
                }
                context.stroke(flagPath, with: .color(.black.opacity(0.72)), lineWidth: 1.0)
            }
            return
        }

        let path = Path { path in
            path.move(to: stem.start)
            path.addLine(to: stem.end)
        }
        context.stroke(
            path,
            with: .color(.black.opacity(stem.isHighlighted ? 0.9 : 0.72)),
            lineWidth: stem.isGrace ? 0.9 : 1.3
        )

        if (chord.noteValue == .eighth) || stem.isGrace {
            drawFlag(from: stem, in: &context, layout: layout)
        }
    }

    private func drawFlag(
        from stem: StaffStemGeometry,
        in context: inout GraphicsContext,
        layout: StaffCanvasLayout
    ) {
        let flagDirection: CGFloat = stem.direction == .up ? 1 : -1
        let flagPath = Path { path in
            path.move(to: stem.end)
            path.addCurve(
                to: CGPoint(
                    x: stem.end.x + layout.noteWidth * 0.62,
                    y: stem.end.y + layout.lineSpacing * 0.72 * flagDirection
                ),
                control1: CGPoint(
                    x: stem.end.x + layout.noteWidth * 0.50,
                    y: stem.end.y + layout.lineSpacing * 0.10 * flagDirection
                ),
                control2: CGPoint(
                    x: stem.end.x + layout.noteWidth * 0.66,
                    y: stem.end.y + layout.lineSpacing * 0.44 * flagDirection
                )
            )
        }
        context.stroke(flagPath, with: .color(.black.opacity(0.72)), lineWidth: stem.isGrace ? 1.0 : 1.3)
    }

    private func drawBeam(
        _ beam: ScrollingStaffNotationBeam,
        chordByID: [String: ScrollingStaffNotationChord],
        itemByID: [String: ScrollingStaffNotationItem],
        in context: inout GraphicsContext,
        layout: StaffCanvasLayout
    ) {
        let stems = beam.chordIDs.compactMap { chordID -> StaffStemGeometry? in
            guard let chord = chordByID[chordID] else { return nil }
            return stemGeometry(for: chord, itemByID: itemByID, layout: layout)
        }
        guard stems.count >= 2 else { return }

        let first = stems[0]
        let last = stems[stems.count - 1]
        guard first.direction == last.direction else { return }

        let direction = first.direction
        let thickness = layout.lineSpacing * 0.42
        let gap = layout.lineSpacing * 0.18
        let yOff = direction == .up ? (thickness + gap) : -(thickness + gap)

        let isHighlighted = stems.contains { $0.isHighlighted }
        let beamOpacity: CGFloat = isHighlighted ? 0.9 : 0.72

        for b in 0 ..< max(1, beam.beamCount) {
            let topYOffset = CGFloat(b) * yOff
            let bottomYOffset = topYOffset + (direction == .up ? thickness : -thickness)

            let topStart = CGPoint(x: first.end.x, y: first.end.y + topYOffset)
            let topEnd = CGPoint(x: last.end.x, y: last.end.y + topYOffset)
            let bottomStart = CGPoint(x: first.end.x, y: first.end.y + bottomYOffset)
            let bottomEnd = CGPoint(x: last.end.x, y: last.end.y + bottomYOffset)

            let beamPath = Path { path in
                path.move(to: topStart)
                path.addLine(to: topEnd)
                path.addLine(to: bottomEnd)
                path.addLine(to: bottomStart)
                path.closeSubpath()
            }
            context.fill(beamPath, with: .color(.black.opacity(beamOpacity)))
        }

        let outerYOffset = CGFloat(max(0, beam.beamCount - 1)) * yOff
        for stem in stems {
            guard stem.direction == direction else { continue }
            let baseEndY: CGFloat
            if abs(last.end.x - first.end.x) < 0.01 {
                baseEndY = first.end.y
            } else {
                let t = (stem.end.x - first.end.x) / (last.end.x - first.end.x)
                baseEndY = first.end.y + t * (last.end.y - first.end.y)
            }
            let stemEndY = baseEndY + outerYOffset
            let stemPath = Path { path in
                path.move(to: stem.start)
                path.addLine(to: CGPoint(x: stem.end.x, y: stemEndY))
            }
            context.stroke(
                stemPath,
                with: .color(.black.opacity(stem.isHighlighted ? 0.9 : 0.72)),
                lineWidth: stem.isGrace ? 0.9 : 1.3
            )
        }
    }

    private func stemGeometry(
        for chord: ScrollingStaffNotationChord,
        itemByID: [String: ScrollingStaffNotationItem],
        layout: StaffCanvasLayout
    ) -> StaffStemGeometry? {
        let items = chord.itemIDs.compactMap { itemByID[$0] }
        guard items.isEmpty == false else { return nil }
        let centers = items.map { noteHeadCenter(for: $0, layout: layout) }
        let minX = centers.map(\.x).min() ?? layout.xPosition(chord.xPosition)
        let maxX = centers.map(\.x).max() ?? layout.xPosition(chord.xPosition)
        let minY = centers.map(\.y).min() ?? layout.yPosition(staffStep: 4)
        let maxY = centers.map(\.y).max() ?? layout.yPosition(staffStep: 4)
        let isGrace = items.contains { $0.isGrace }
        let stemHeight = layout.stemHeight(isGrace: isGrace)
        let isHighlighted = items.contains { $0.isHighlighted }

        switch chord.stemDirection {
            case .up:
                let x = maxX + rotatedNoteheadEdgeOffset(layout: layout)
                return StaffStemGeometry(
                    start: CGPoint(x: x, y: maxY),
                    end: CGPoint(x: x, y: minY - stemHeight),
                    direction: .up,
                    isGrace: isGrace,
                    isHighlighted: isHighlighted
                )
            case .down:
                let x = minX - rotatedNoteheadEdgeOffset(layout: layout)
                return StaffStemGeometry(
                    start: CGPoint(x: x, y: minY),
                    end: CGPoint(x: x, y: maxY + stemHeight),
                    direction: .down,
                    isGrace: isGrace,
                    isHighlighted: isHighlighted
                )
        }
    }

    private func drawTie(
        for item: ScrollingStaffNotationItem,
        in context: inout GraphicsContext,
        layout: StaffCanvasLayout
    ) {
        guard item.tieStart, let tieEndXPosition = item.tieEndXPosition else { return }
        let center = noteHeadCenter(for: item, layout: layout)
        let x = center.x
        let y = center.y + layout.noteHeight * 0.78
        let endX = layout.xPosition(tieEndXPosition)
        let startX = min(x, endX) + layout.noteWidth * 0.45
        let finalX = max(x, endX) - layout.noteWidth * 0.45
        guard finalX > startX + layout.noteWidth * 0.5 else { return }
        let path = Path { path in
            path.move(to: CGPoint(x: startX, y: y))
            path.addQuadCurve(
                to: CGPoint(x: finalX, y: y),
                control: CGPoint(x: (startX + finalX) / 2, y: y + layout.lineSpacing * 0.72)
            )
        }
        context.stroke(path, with: .color(.black.opacity(0.38)), lineWidth: 1.2)
    }

    private func drawArpeggiate(
        at center: CGPoint,
        in context: inout GraphicsContext,
        layout: StaffCanvasLayout
    ) {
        let height = layout.lineSpacing * 2.35
        let path = Path { path in
            let top = center.y - height / 2
            path.move(to: CGPoint(x: center.x, y: top))
            var y = top
            while y < top + height {
                path.addCurve(
                    to: CGPoint(x: center.x, y: y + layout.lineSpacing * 0.42),
                    control1: CGPoint(x: center.x - layout.noteWidth * 0.26, y: y + layout.lineSpacing * 0.1),
                    control2: CGPoint(x: center.x + layout.noteWidth * 0.26, y: y + layout.lineSpacing * 0.3)
                )
                y += layout.lineSpacing * 0.42
            }
        }
        context.stroke(path, with: .color(.black.opacity(0.55)), lineWidth: 1.1)
    }

    private func drawArticulations(
        for item: ScrollingStaffNotationItem,
        at center: CGPoint,
        in context: inout GraphicsContext,
        layout: StaffCanvasLayout
    ) {
        guard item.articulations.isEmpty == false else { return }
        let above = item.staffStep < 4
        var y = center.y + (above ? -layout.lineSpacing * 1.55 : layout.lineSpacing * 1.55)

        func drawText(_ text: String, size: CGFloat = 13) {
            context.draw(
                Text(text).font(.system(size: size, weight: .semibold)).foregroundStyle(.black.opacity(0.75)),
                at: CGPoint(x: center.x, y: y),
                anchor: .center
            )
            y += above ? -layout.lineSpacing * 0.66 : layout.lineSpacing * 0.66
        }

        if item.articulations.contains(.staccato) {
            drawText("•", size: 14)
        }
        if item.articulations.contains(.staccatissimo) {
            drawText("▾", size: 13)
        }
        if item.articulations.contains(.tenuto) || item.articulations.contains(.detachedLegato) {
            drawText("—", size: 13)
        }
        if item.articulations.contains(.accent) {
            drawText(">", size: 14)
        }
        if item.articulations.contains(.marcato) {
            drawText("^", size: 14)
        }
    }

    private func drawFingering(
        for item: ScrollingStaffNotationItem,
        at center: CGPoint,
        in context: inout GraphicsContext,
        layout: StaffCanvasLayout
    ) {
        guard let fingering = item.fingeringText, fingering.isEmpty == false else { return }
        let y = center.y - layout.lineSpacing * 2.15
        context.draw(
            Text(fingering)
                .font(.system(size: max(9, layout.lineSpacing * 0.68), weight: .medium))
                .foregroundStyle(.secondary),
            at: CGPoint(x: center.x + layout.noteWidth * 0.1, y: y),
            anchor: .center
        )
    }

    private func drawGraceSlash(
        for item: ScrollingStaffNotationItem,
        at center: CGPoint,
        in context: inout GraphicsContext,
        layout: StaffCanvasLayout
    ) {
        let path = Path { path in
            path.move(to: CGPoint(x: center.x - layout.noteWidth * 0.65, y: center.y + layout.noteHeight * 0.52))
            path.addLine(to: CGPoint(x: center.x + layout.noteWidth * 0.65, y: center.y - layout.noteHeight * 0.60))
        }
        context.stroke(path, with: .color(.black.opacity(0.6)), lineWidth: 1.1)
    }

    private func noteHeadCenter(for item: ScrollingStaffNotationItem, layout: StaffCanvasLayout) -> CGPoint {
        CGPoint(
            x: layout.xPosition(item.xPosition) + CGFloat(item.noteHeadXOffset) * layout.noteWidth,
            y: layout.yPosition(staffStep: item.staffStep)
        )
    }

    private func rotatedNoteheadEdgeOffset(layout: StaffCanvasLayout) -> CGFloat {
        let a = layout.noteWidth / 2
        let b = layout.noteHeight / 2
        let theta: CGFloat = -12.0 * .pi / 180
        let cosT = cos(theta)
        let sinT = sin(theta)
        let edgeX = sqrt(a * a * cosT * cosT + b * b * sinT * sinT)
        return edgeX + 1.5
    }
}

private struct StaffStemGeometry {
    let start: CGPoint
    let end: CGPoint
    let direction: ScrollingStaffStemDirection
    let isGrace: Bool
    let isHighlighted: Bool
}

private struct StaffCanvasLayout {
    let size: CGSize
    let contextWidth: CGFloat

    init(size: CGSize, notationContext: ScrollingStaffNotationContext) {
        self.size = size
        let ls = max(10, min(18, size.height * 0.09))
        let clefRight = 4 + ls * 2.75
        var right = clefRight
        if let fifths = notationContext.keySignatureFifths, fifths != 0 {
            right += ls * 0.25
            right += CGFloat(min(abs(fifths), 7)) * ls * 0.55
        } else if let text = notationContext.keySignatureText, !text.isEmpty {
            right += max(ls * 1.2, CGFloat(text.count) * ls * 0.46)
        }
        if let tsText = notationContext.timeSignatureText, !tsText.isEmpty {
            right += ls * 0.35
            right += ls * 0.7
        }
        right += ls * 0.6
        self.contextWidth = max(right - 4, ls * 5)
    }

    var contextMinX: CGFloat {
        4
    }

    var contentMinX: CGFloat {
        contextMinX + contextWidth
    }

    var contentMaxX: CGFloat {
        min(size.width - 18, size.width * 0.96)
    }

    var lineSpacing: CGFloat {
        max(10, min(18, size.height * 0.09))
    }

    var topLineY: CGFloat {
        (size.height - lineSpacing * 4) / 2
    }

    var bottomLineY: CGFloat {
        topLineY + lineSpacing * 4
    }

    var noteWidth: CGFloat {
        lineSpacing * 1.05
    }

    var noteHeight: CGFloat {
        lineSpacing * 0.70
    }

    func stemHeight(isGrace: Bool) -> CGFloat {
        lineSpacing * (isGrace ? 2.2 : 3.0)
    }

    func durationWidth(for item: ScrollingStaffNotationItem) -> CGFloat {
        let normalized = min(1.0, Double(item.durationTicks) / 1_920)
        return noteWidth * 1.8 + CGFloat(normalized) * noteWidth * 3.8
    }

    func xPosition(_ normalized: Double) -> CGFloat {
        let clamped = max(-0.2, min(1.2, normalized))
        return contentMinX + CGFloat(clamped) * (contentMaxX - contentMinX)
    }

    func yPosition(staffStep: Int) -> CGFloat {
        bottomLineY - CGFloat(staffStep) * lineSpacing / 2
    }
}

#Preview {
    ScrollingStaffNotationView(
        guides: [
            previewGuide(id: 1, tick: 0, midiNotes: [60]),
            previewGuide(id: 2, tick: 480, midiNotes: [64, 67]),
            previewGuide(id: 3, tick: 960, midiNotes: [61, 72]),
        ],
        currentGuide: previewGuide(id: 2, tick: 480, midiNotes: [64, 67]),
        halfWindowTicks: 960
    )
    .frame(width: 720, height: 210)
    .padding()
}

private func previewGuide(id: Int, tick: Int, midiNotes: [Int]) -> PianoHighlightGuide {
    let notes = midiNotes.map { midiNote in
        PianoHighlightNote(
            occurrenceID: "preview-\(id)-\(midiNote)",
            midiNote: midiNote,
            staff: 1,
            voice: 1,
            velocity: 96,
            onTick: tick,
            offTick: tick + 480,
            fingeringText: nil
        )
    }

    return PianoHighlightGuide(
        id: id,
        kind: .trigger,
        tick: tick,
        durationTicks: 480,
        practiceStepIndex: id - 1,
        activeNotes: notes,
        triggeredNotes: notes,
        releasedMIDINotes: []
    )
}
