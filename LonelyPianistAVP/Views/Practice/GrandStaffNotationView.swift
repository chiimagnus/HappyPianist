import SwiftUI

struct GrandStaffNotationView: View {
    let guides: [PianoHighlightGuide]
    let currentGuide: PianoHighlightGuide?
    let measureSpans: [MusicXMLMeasureSpan]
    let context: GrandStaffNotationContext?
    var scrollTickProvider: (() -> Double?)?

    private let layoutService = GrandStaffNotationLayoutService()
    private let viewportLayoutService = GrandStaffNotationViewportLayoutService()
    private let fixedLineSpacing: CGFloat = 14
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            let lineSpacing = fixedLineSpacing
            let contentWidth = resolvedContentWidth(for: proxy.size, lineSpacing: lineSpacing)
            let halfWindowTicks = resolvedHalfWindowTicks(contentWidth: contentWidth, lineSpacing: lineSpacing)

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
                context: layout.context
            )
            let chordsByID = Dictionary(uniqueKeysWithValues: layout.chords.map { ($0.id, $0) })
            let itemsByChordID = Dictionary(grouping: layout.items, by: { $0.chordID ?? "" })

            ScrollView(.vertical) {
                Canvas { context, _ in
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
            }
            .scrollIndicators(.hidden)
        }
        .accessibilityLabel("Grand Staff 五线谱")
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

    private func drawStems(
        _ chords: [GrandStaffNotationChord],
        beamedChordIDs: Set<String>,
        itemsByChordID: [String: [GrandStaffNotationItem]],
        in context: GraphicsContext,
        layout: GrandStaffNotationViewportLayoutService.Layout
    ) {
        let stemStroke = StrokeStyle(lineWidth: max(1, layout.lineSpacing * 0.14), lineCap: .round)
        let defaultStemLength = layout.lineSpacing * 3.2

        for chord in chords {
            if beamedChordIDs.contains(chord.id) { continue }
            guard chord.noteValue != .whole else { continue }
            guard let chordItems = itemsByChordID[chord.id], chordItems.isEmpty == false else { continue }

            let stem = resolvedStemGeometry(
                chord: chord,
                chordItems: chordItems,
                stemLength: defaultStemLength,
                layout: layout
            )

            var path = Path()
            path.move(to: stem.start)
            path.addLine(to: stem.end)
            context.stroke(path, with: .color(Color.primary.opacity(0.45)), style: stemStroke)

            if chord.noteValue == .eighth || chord.noteValue == .sixteenth || chord.noteValue == .thirtySecond {
                drawFlag(stemEnd: stem.end, direction: chord.stemDirection, in: context, layout: layout)
            }
        }
    }

    private func drawBeams(
        _ beams: [GrandStaffNotationBeam],
        chordsByID: [String: GrandStaffNotationChord],
        itemsByChordID: [String: [GrandStaffNotationItem]],
        in context: GraphicsContext,
        layout: GrandStaffNotationViewportLayoutService.Layout
    ) {
        guard beams.isEmpty == false else { return }

        let stemStroke = StrokeStyle(lineWidth: max(1, layout.lineSpacing * 0.14), lineCap: .round)
        let beamStroke = StrokeStyle(lineWidth: max(2, layout.lineSpacing * 0.42), lineCap: .butt)
        let defaultStemLength = layout.lineSpacing * 3.2
        let beamGap = max(1.2, layout.lineSpacing * 0.28)
        let beamStackStride = beamStroke.lineWidth + beamGap
        let minStemLength = layout.lineSpacing * 2.6

        for beam in beams {
            let chords = beam.chordIDs.compactMap { chordsByID[$0] }.sorted { $0.xPosition < $1.xPosition }
            guard chords.count >= 2 else { continue }

            let direction = chords.first?.stemDirection ?? .up

            var stemByChordID: [String: (start: CGPoint, end: CGPoint)] = [:]
            stemByChordID.reserveCapacity(chords.count)

            for chord in chords {
                guard let chordItems = itemsByChordID[chord.id], chordItems.isEmpty == false else { continue }
                let stem = resolvedStemGeometry(
                    chord: chord,
                    chordItems: chordItems,
                    stemLength: defaultStemLength,
                    layout: layout
                )
                stemByChordID[chord.id] = (start: stem.start, end: stem.end)
            }

            guard let firstChord = chords.first, let lastChord = chords.last else { continue }
            guard let firstStem = stemByChordID[firstChord.id],
                  let lastStem = stemByChordID[lastChord.id] else { continue }

            let x1 = firstStem.end.x
            let xN = lastStem.end.x
            let span = max(1, abs(xN - x1))

            let rawDeltaY = lastStem.end.y - firstStem.end.y
            let maxDeltaY = layout.lineSpacing * 1.5
            let clampedDeltaY = max(-maxDeltaY, min(maxDeltaY, rawDeltaY))
            let slope = clampedDeltaY / span

            func yOnBeam(at x: CGFloat, offset: CGFloat) -> CGFloat {
                firstStem.end.y + slope * (x - x1) + offset
            }

            // Shift the beam so every stem is at least `minStemLength`,
            // and maintain a small clearance from the nearest notehead.
            let noteheadClearance = layout.lineSpacing * 0.8
            var requiredOffset: CGFloat = 0

            for chord in chords {
                guard let stem = stemByChordID[chord.id] else { continue }
                let chordBeamY = yOnBeam(at: stem.end.x, offset: 0)

                if direction == .up {
                    let allowedMaxY = stem.start.y - minStemLength
                    if chordBeamY > allowedMaxY {
                        requiredOffset = min(requiredOffset, allowedMaxY - chordBeamY)
                    }
                    let clearanceMaxY = stem.start.y - noteheadClearance
                    if chordBeamY > clearanceMaxY {
                        requiredOffset = min(requiredOffset, clearanceMaxY - chordBeamY)
                    }
                } else {
                    let allowedMinY = stem.start.y + minStemLength
                    if chordBeamY < allowedMinY {
                        requiredOffset = max(requiredOffset, allowedMinY - chordBeamY)
                    }
                    let clearanceMinY = stem.start.y + noteheadClearance
                    if chordBeamY < clearanceMinY {
                        requiredOffset = max(requiredOffset, clearanceMinY - chordBeamY)
                    }
                }
            }

            let firstX = x1
            let lastX = xN

            // Primary beam: the one furthest from the noteheads.
            var primaryPath = Path()
            primaryPath.move(to: CGPoint(x: firstX, y: yOnBeam(at: firstX, offset: requiredOffset)))
            primaryPath.addLine(to: CGPoint(x: lastX, y: yOnBeam(at: lastX, offset: requiredOffset)))
            context.stroke(primaryPath, with: .color(Color.primary.opacity(0.42)), style: beamStroke)

            // Secondary / tertiary beams: segmented based on each chord's rhythmic value.
            if beam.beamCount >= 2 {
                let levels = 2 ... beam.beamCount
                for level in levels {
                    let stride = CGFloat(level - 1) * beamStackStride
                    let secondaryOffset = (direction == .up) ? (requiredOffset + stride) : (requiredOffset - stride)

                    var activeSegment: [GrandStaffNotationChord] = []

                    func flushSegment() {
                        guard activeSegment.count >= 2 else {
                            activeSegment.removeAll(keepingCapacity: true)
                            return
                        }
                        let firstChord = activeSegment.first
                        let lastChord = activeSegment.last
                        let startX = firstChord.flatMap { stemByChordID[$0.id]?.end.x } ?? layout
                            .xPosition(firstChord?.xPosition ?? 0)
                        let endX = lastChord.flatMap { stemByChordID[$0.id]?.end.x } ?? layout
                            .xPosition(lastChord?.xPosition ?? 0)
                        var path = Path()
                        path.move(to: CGPoint(x: startX, y: yOnBeam(at: startX, offset: secondaryOffset)))
                        path.addLine(to: CGPoint(x: endX, y: yOnBeam(at: endX, offset: secondaryOffset)))
                        context.stroke(path, with: .color(Color.primary.opacity(0.42)), style: beamStroke)
                        activeSegment.removeAll(keepingCapacity: true)
                    }

                    for chord in chords {
                        if chordBeamCount(for: chord.noteValue) >= level {
                            activeSegment.append(chord)
                        } else {
                            flushSegment()
                        }
                    }
                    flushSegment()
                }
            }

            for chord in chords {
                guard let stem = stemByChordID[chord.id] else { continue }
                let adjustedEnd = CGPoint(x: stem.end.x, y: yOnBeam(at: stem.end.x, offset: requiredOffset))
                var path = Path()
                path.move(to: stem.start)
                path.addLine(to: adjustedEnd)
                context.stroke(path, with: .color(Color.primary.opacity(0.45)), style: stemStroke)
            }
        }
    }

    private func chordBeamCount(for noteValue: GrandStaffNoteValue) -> Int {
        switch noteValue {
            case .eighth:
                1
            case .sixteenth:
                2
            case .thirtySecond:
                3
            default:
                0
        }
    }

    private func drawFlag(
        stemEnd: CGPoint,
        direction: GrandStaffStemDirection,
        in context: GraphicsContext,
        layout: GrandStaffNotationViewportLayoutService.Layout
    ) {
        let dx = layout.noteWidth * 0.55
        let dy = layout.noteHeight * 0.85
        let stroke = StrokeStyle(lineWidth: max(1, layout.lineSpacing * 0.14), lineCap: .round)

        var path = Path()
        if direction == .up {
            path.move(to: stemEnd)
            path.addLine(to: CGPoint(x: stemEnd.x + dx, y: stemEnd.y + dy))
        } else {
            path.move(to: stemEnd)
            path.addLine(to: CGPoint(x: stemEnd.x + dx, y: stemEnd.y - dy))
        }
        context.stroke(path, with: .color(Color.primary.opacity(0.45)), style: stroke)
    }

    private func resolvedStemGeometry(
        chord: GrandStaffNotationChord,
        chordItems: [GrandStaffNotationItem],
        stemLength: CGFloat,
        layout: GrandStaffNotationViewportLayoutService.Layout
    ) -> (start: CGPoint, end: CGPoint) {
        let x = layout.xPosition(chord.xPosition)
        let steps = chordItems.map(\.staffStep)
        let staffNumber = chordItems.first?.staffNumber ?? 1

        if chord.stemDirection == .up {
            let topStep = steps.max() ?? 4
            let startY = layout.yPosition(staffStep: topStep, staffNumber: staffNumber)
            let startX = x + layout.noteWidth * 0.46
            let end = CGPoint(x: startX, y: startY - stemLength)
            return (CGPoint(x: startX, y: startY), end)
        } else {
            let bottomStep = steps.min() ?? 4
            let startY = layout.yPosition(staffStep: bottomStep, staffNumber: staffNumber)
            let startX = x - layout.noteWidth * 0.46
            let end = CGPoint(x: startX, y: startY + stemLength)
            return (CGPoint(x: startX, y: startY), end)
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
            let accidental = Text("\u{E262}").font(.custom("Bravura", size: layout.lineSpacing * 1.05))
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
    .frame(width: 800, height: 260)
    .padding()
}
