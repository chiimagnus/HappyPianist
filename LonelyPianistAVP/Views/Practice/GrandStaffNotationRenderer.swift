import SwiftUI

struct GrandStaffNotationRenderer: GrandStaffNotationRendererProtocol {
    private let displayScale: CGFloat

    init(displayScale: CGFloat = 1) {
        self.displayScale = displayScale
    }

    func draw(
        presentation: GrandStaffNotationPresentation,
        in context: GraphicsContext,
        displayScale: CGFloat
    ) {
        let renderer = GrandStaffNotationRenderer(displayScale: displayScale)
        renderer.drawInternal(presentation, in: context)
    }

    private func drawInternal(
        _ presentation: GrandStaffNotationPresentation,
        in context: GraphicsContext
    ) {
        let layout = presentation.viewportLayout
        let practiceHandMode = presentation.practiceHandMode
        var translatedContext = context
        translatedContext.translateBy(x: 0, y: alignedToPixel(layout.canvasYOffset))
        drawGrandStaffLines(in: translatedContext, layout: layout)
        drawContext(in: translatedContext, layout: layout)
        drawBarlines(presentation.notationLayout.barlines, in: translatedContext, layout: layout)
        drawBeams(
            presentation.notationLayout.beams,
            chordsByID: presentation.chordsByID,
            itemsByChordID: presentation.itemsByChordID,
            in: translatedContext,
            practiceHandMode: practiceHandMode,
            layout: layout
        )
        drawStems(
            presentation.notationLayout.chords,
            beamedChordIDs: presentation.beamedChordIDs,
            itemsByChordID: presentation.itemsByChordID,
            in: translatedContext,
            practiceHandMode: practiceHandMode,
            layout: layout
        )
        drawItems(
            presentation.notationLayout.items,
            ledgerStepsByItemID: presentation.ledgerStepsByItemID,
            in: translatedContext,
            practiceHandMode: practiceHandMode,
            layout: layout
        )
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

    private func drawContext(
        in context: GraphicsContext,
        layout: GrandStaffNotationViewportLayoutService.Layout
    ) {
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
                xStart: timeMinX,
                centerY: trebleKeyCenterY,
                font: timeSignatureFont,
                verticalOffset: layout.lineSpacing * 0.78,
                in: context
            )
            drawTimeSignature(
                text: staffContext.timeSignatureText,
                xStart: timeMinX,
                centerY: bassKeyCenterY,
                font: timeSignatureFont,
                verticalOffset: layout.lineSpacing * 0.78,
                in: context
            )
        } else {
            drawTimeSignature(
                text: staffContext.timeSignatureText,
                xStart: timeMinXBase,
                centerY: trebleKeyCenterY,
                font: timeSignatureFont,
                verticalOffset: layout.lineSpacing * 0.78,
                in: context
            )
            drawTimeSignature(
                text: staffContext.timeSignatureText,
                xStart: timeMinXBase,
                centerY: bassKeyCenterY,
                font: timeSignatureFont,
                verticalOffset: layout.lineSpacing * 0.78,
                in: context
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
        xStart: CGFloat,
        centerY: CGFloat,
        font: Font,
        verticalOffset: CGFloat,
        in context: GraphicsContext
    ) {
        guard let text, text.isEmpty == false else { return }

        let parts = text.split(separator: "/")
        guard parts.count == 2, let top = Int(parts[0]), let bottom = Int(parts[1]) else {
            context.draw(Text(text).font(font), at: CGPoint(x: xStart, y: centerY), anchor: .leading)
            return
        }

        func digitGlyph(_ digit: Int) -> String? {
            guard (0 ... 9).contains(digit) else { return nil }
            guard let scalar = UnicodeScalar(0xE080 + digit) else { return nil }
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

        context.draw(Text(topGlyphs).font(font), at: CGPoint(x: xStart, y: centerY - verticalOffset), anchor: .leading)
        context.draw(Text(bottomGlyphs).font(font), at: CGPoint(x: xStart, y: centerY + verticalOffset), anchor: .leading)
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
        ledgerStepsByItemID: [String: [Int]],
        in context: GraphicsContext,
        practiceHandMode: PracticeHandMode,
        layout: GrandStaffNotationViewportLayoutService.Layout
    ) {
        guard items.isEmpty == false else { return }

        for item in items {
            let x = layout.xPosition(item.xPosition) + CGFloat(item.noteHeadXOffset) * layout.noteWidth
            let y = layout.yPosition(staffStep: item.staffStep, staffNumber: item.staffNumber)
            let fadeScale = handFadeScale(for: item.hand, practiceHandMode: practiceHandMode)
            drawNoteHead(item: item, x: x, y: y, in: context, fadeScale: fadeScale, layout: layout)

            for step in ledgerStepsByItemID[item.id] ?? [] {
                let ledgerY = alignedToPixel(layout.yPosition(staffStep: step, staffNumber: item.staffNumber))
                var path = Path()
                path.move(to: CGPoint(x: x - layout.noteWidth * 0.65, y: ledgerY))
                path.addLine(to: CGPoint(x: x + layout.noteWidth * 0.65, y: ledgerY))
                context.stroke(
                    path,
                    with: .color(Color.primary.opacity(0.22 * fadeScale)),
                    style: .init(lineWidth: 1)
                )
            }
        }
    }

    private func drawStems(
        _ chords: [GrandStaffNotationChord],
        beamedChordIDs: Set<String>,
        itemsByChordID: [String: [GrandStaffNotationItem]],
        in context: GraphicsContext,
        practiceHandMode: PracticeHandMode,
        layout: GrandStaffNotationViewportLayoutService.Layout
    ) {
        let stemStroke = StrokeStyle(lineWidth: max(1, layout.lineSpacing * 0.14), lineCap: .round)
        let defaultStemLength = layout.lineSpacing * 3.2

        for chord in chords {
            if beamedChordIDs.contains(chord.id) { continue }
            guard chord.noteValue != .whole else { continue }
            guard let chordItems = itemsByChordID[chord.id], chordItems.isEmpty == false else { continue }

            let fadeScale = chordFadeScale(for: chordItems, practiceHandMode: practiceHandMode)
            let stem = resolvedStemGeometry(
                chord: chord,
                chordItems: chordItems,
                stemLength: defaultStemLength,
                layout: layout
            )

            var path = Path()
            path.move(to: stem.start)
            path.addLine(to: stem.end)
            context.stroke(path, with: .color(Color.primary.opacity(0.45 * fadeScale)), style: stemStroke)

            if chord.noteValue == .eighth || chord.noteValue == .sixteenth || chord.noteValue == .thirtySecond {
                drawFlag(
                    stemEnd: stem.end,
                    direction: chord.stemDirection,
                    in: context,
                    fadeScale: fadeScale,
                    layout: layout
                )
            }
        }
    }

    private func drawBeams(
        _ beams: [GrandStaffNotationBeam],
        chordsByID: [String: GrandStaffNotationChord],
        itemsByChordID: [String: [GrandStaffNotationItem]],
        in context: GraphicsContext,
        practiceHandMode: PracticeHandMode,
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

            let fadeScale = chords
                .compactMap { chord -> Double? in
                    guard let chordItems = itemsByChordID[chord.id], chordItems.isEmpty == false else { return nil }
                    return chordFadeScale(for: chordItems, practiceHandMode: practiceHandMode)
                }
                .max() ?? 1.0

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

            var primaryPath = Path()
            primaryPath.move(to: CGPoint(x: x1, y: yOnBeam(at: x1, offset: requiredOffset)))
            primaryPath.addLine(to: CGPoint(x: xN, y: yOnBeam(at: xN, offset: requiredOffset)))
            context.stroke(primaryPath, with: .color(Color.primary.opacity(0.42 * fadeScale)), style: beamStroke)

            if beam.beamCount >= 2 {
                for level in 2 ... beam.beamCount {
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
                        context.stroke(path, with: .color(Color.primary.opacity(0.42 * fadeScale)), style: beamStroke)
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
                let chordScale = itemsByChordID[chord.id].map { chordFadeScale(for: $0, practiceHandMode: practiceHandMode) } ?? 1.0
                context.stroke(path, with: .color(Color.primary.opacity(0.45 * chordScale)), style: stemStroke)
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
        fadeScale: Double,
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
        context.stroke(path, with: .color(Color.primary.opacity(0.45 * fadeScale)), style: stroke)
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
        fadeScale: Double,
        layout: GrandStaffNotationViewportLayoutService.Layout
    ) {
        let rect = CGRect(
            x: x - layout.noteWidth / 2,
            y: y - layout.noteHeight / 2,
            width: layout.noteWidth,
            height: layout.noteHeight
        )
        let path = Path(ellipseIn: rect)
        let baseOpacity: Double = item.isHighlighted ? 1.0 : 0.55
        context.fill(path, with: .color(Color.primary.opacity(baseOpacity * fadeScale)))

        if item.showsSharpAccidental {
            let accidentalOpacity = min(1.0, 0.85 * fadeScale)
            let accidental = Text("\u{E262}")
                .font(.custom("Bravura", size: layout.lineSpacing * 1.05))
                .foregroundStyle(Color.primary.opacity(accidentalOpacity))
            context.draw(accidental, at: CGPoint(x: x - layout.noteWidth * 1.0, y: y))
        }
    }

    private func handFadeScale(for hand: ScoreHand, practiceHandMode: PracticeHandMode) -> Double {
        guard let focusedHand = practiceHandMode.focusedHand else { return 1.0 }
        return hand == focusedHand ? 1.0 : 0.45
    }

    private func chordFadeScale(for chordItems: [GrandStaffNotationItem], practiceHandMode: PracticeHandMode) -> Double {
        chordItems.map { handFadeScale(for: $0.hand, practiceHandMode: practiceHandMode) }.max() ?? 1.0
    }

    private func alignedToPixel(_ value: CGFloat) -> CGFloat {
        guard displayScale.isFinite, displayScale > 0 else { return value }
        return (value * displayScale).rounded() / displayScale
    }
}
