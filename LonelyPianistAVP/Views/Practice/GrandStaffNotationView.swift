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

    var body: some View {
        GeometryReader { proxy in
            let layout = layoutService.makeLayout(
                guides: guides,
                currentGuide: currentGuide,
                measureSpans: measureSpans,
                context: context,
                scrollTick: scrollTickProvider?() ?? nil
            )

            let viewLayout = viewportLayoutService.makeLayout(
                size: proxy.size,
                lineSpacing: fixedLineSpacing,
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
                    drawBeams(layout.beams, chordsByID: chordsByID, itemsByChordID: itemsByChordID, in: context, layout: viewLayout)
                    drawStems(layout.chords, beamedChordIDs: Set(layout.beams.flatMap(\.chordIDs)), itemsByChordID: itemsByChordID, in: context, layout: viewLayout)
                    drawItems(layout.items, in: context, layout: viewLayout)
                }
                .frame(width: proxy.size.width, height: viewLayout.requiredHeight)
            }
            .scrollIndicators(.hidden)
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
            guard let firstStem = stemByChordID[firstChord.id], let lastStem = stemByChordID[lastChord.id] else { continue }

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
                let levels = 2...beam.beamCount
                for level in levels {
                    let stride = CGFloat(level - 1) * beamStackStride
                    let secondaryOffset = (direction == .up) ? (requiredOffset + stride) : (requiredOffset - stride)

                    var activeSegment: [GrandStaffNotationChord] = []

                    func flushSegment() {
                        guard activeSegment.count >= 2 else {
                            activeSegment.removeAll(keepingCapacity: true)
                            return
                        }
                        let startX = layout.xPosition(activeSegment.first?.xPosition ?? 0)
                        let endX = layout.xPosition(activeSegment.last?.xPosition ?? 0)
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
                return 1
            case .sixteenth:
                return 2
            case .thirtySecond:
                return 3
            default:
                return 0
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
    .frame(width: 800, height: 260)
    .padding()
}
