import SwiftUI

struct GrandStaffNotationRenderer {
    private let displayScale: CGFloat
    private let engravingMetrics = GrandStaffEngravingMetrics()
    private let chordLayoutService = GrandStaffChordLayoutService()

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
        drawLedgerLines(
            presentation.notationLayout.ledgerLines,
            in: translatedContext,
            layout: layout
        )
        drawRests(
            presentation.notationLayout.rests,
            in: translatedContext,
            layout: layout
        )
        drawItems(
            presentation.notationLayout.items,
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
        let stroke = StrokeStyle(lineWidth: strokeWidth(engravingMetrics.staffLineThickness, layout: layout))

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
        let glyph = (isSharp ? GrandStaffGlyphToken.accidentalSharp : .accidentalFlat).glyph
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
            GrandStaffGlyphToken.timeSignatureDigit(digit)?.glyph
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
        in context: GraphicsContext,
        practiceHandMode: PracticeHandMode,
        layout: GrandStaffNotationViewportLayoutService.Layout
    ) {
        guard items.isEmpty == false else { return }

        for item in items {
            let glyphScale = engravingMetrics.glyphScale(isGrace: item.isGrace)
            let x = layout.xPosition(item.xPosition)
                + item.noteheadXOffset * layout.noteheadColumnWidth * glyphScale
            let y = layout.yPosition(staffStep: item.staffStep, staffNumber: item.staffNumber)
            let fadeScale = handFadeScale(for: item.hand, practiceHandMode: practiceHandMode)

            drawNoteHead(
                item: item,
                chordBaseX: layout.xPosition(item.xPosition),
                x: x,
                y: y,
                in: context,
                fadeScale: fadeScale,
                layout: layout
            )
        }
    }

    private func drawLedgerLines(
        _ ledgerLines: [GrandStaffNotationLedgerLine],
        in context: GraphicsContext,
        layout: GrandStaffNotationViewportLayoutService.Layout
    ) {
        for ledgerLine in ledgerLines {
            let baseX = layout.xPosition(ledgerLine.xPosition)
            let y = alignedToPixel(layout.yPosition(
                staffStep: ledgerLine.staffStep,
                staffNumber: ledgerLine.staffNumber
            ))
            var path = Path()
            path.move(to: CGPoint(
                x: baseX + ledgerLine.minXOffsetStaffSpaces * layout.lineSpacing,
                y: y
            ))
            path.addLine(to: CGPoint(
                x: baseX + ledgerLine.maxXOffsetStaffSpaces * layout.lineSpacing,
                y: y
            ))
            context.stroke(
                path,
                with: .color(Color.primary.opacity(0.22)),
                style: .init(lineWidth: strokeWidth(engravingMetrics.ledgerLineThickness, layout: layout))
            )
        }
    }

    private func drawRests(
        _ rests: [GrandStaffNotationRest],
        in context: GraphicsContext,
        layout: GrandStaffNotationViewportLayoutService.Layout
    ) {
        for rest in rests {
            guard let token = rest.glyphToken else { continue }
            let color = resolvedNotationColor(isHighlighted: rest.isHighlighted, staffNumber: rest.staffNumber)
            drawGlyph(
                token,
                baselineAt: CGPoint(
                    x: layout.xPosition(rest.xPosition),
                    y: layout.yPosition(staffStep: rest.staffStep, staffNumber: rest.staffNumber)
                ),
                centeredOnAdvance: true,
                scale: 1,
                color: color,
                opacity: rest.isHighlighted ? 1 : 0.55,
                in: context,
                layout: layout
            )
            if rest.dotCount > 0,
               let restBounds = engravingMetrics.bounds(for: token),
               let dotBounds = engravingMetrics.bounds(for: .augmentationDot) {
                let dotStaffStep = rest.staffStep + 1
                let firstDotOffset = restBounds.maxX + engravingMetrics.dotNoteheadGap - dotBounds.minX
                for dotIndex in 0 ..< rest.dotCount {
                    drawGlyph(
                        .augmentationDot,
                        baselineAt: CGPoint(
                            x: layout.xPosition(rest.xPosition)
                                + (firstDotOffset + Double(dotIndex) * engravingMetrics.dotSpacing)
                                * layout.lineSpacing,
                            y: layout.yPosition(staffStep: dotStaffStep, staffNumber: rest.staffNumber)
                        ),
                        centeredOnAdvance: true,
                        scale: 1,
                        color: color,
                        opacity: rest.isHighlighted ? 1 : 0.55,
                        in: context,
                        layout: layout
                    )
                }
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
        let stemStroke = StrokeStyle(
            lineWidth: strokeWidth(engravingMetrics.stemThickness, layout: layout),
            lineCap: .round
        )

        for chord in chords {
            if beamedChordIDs.contains(chord.id) { continue }
            guard chord.noteValue.hasStem, chord.stem.isVisible else { continue }
            guard let chordItems = itemsByChordID[chord.id], chordItems.isEmpty == false else { continue }

            let fadeScale = chordFadeScale(for: chordItems, practiceHandMode: practiceHandMode)
            let isGrace = chordItems.allSatisfy(\.isGrace)
            let glyphScale = engravingMetrics.glyphScale(isGrace: isGrace)
            guard let stem = chordLayoutService.stemGeometry(
                stem: chord.stem,
                chordX: layout.xPosition(chord.xPosition),
                noteheadWidth: layout.noteheadColumnWidth * glyphScale,
                stemLength: layout.lineSpacing * engravingMetrics.defaultStemLength * glyphScale,
                noteCentersByID: noteCenters(for: chordItems, layout: layout)
            ) else { continue }

            var path = Path()
            path.move(to: stem.start)
            path.addLine(to: stem.end)
            context.stroke(path, with: .color(Color.primary.opacity(0.45 * fadeScale)), style: stemStroke)

            if let flagToken = chord.noteValue.flagGlyphToken(stemDirection: chord.stem.direction) {
                drawFlag(
                    token: flagToken,
                    stemEnd: stem.end,
                    scale: glyphScale,
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

        let stemStroke = StrokeStyle(
            lineWidth: strokeWidth(engravingMetrics.stemThickness, layout: layout),
            lineCap: .round
        )
        let beamStroke = StrokeStyle(
            lineWidth: strokeWidth(engravingMetrics.beamThickness, layout: layout),
            lineCap: .butt
        )
        let beamStackStride = layout.lineSpacing * engravingMetrics.beamSpacing
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

            let direction = chords.first?.stem.direction ?? .up
            var stemByChordID: [String: (start: CGPoint, end: CGPoint)] = [:]
            stemByChordID.reserveCapacity(chords.count)

            for chord in chords {
                guard chord.stem.isVisible, chord.noteValue.hasStem,
                      let chordItems = itemsByChordID[chord.id], chordItems.isEmpty == false
                else { continue }
                let glyphScale = engravingMetrics.glyphScale(isGrace: chordItems.allSatisfy(\.isGrace))
                guard let stem = chordLayoutService.stemGeometry(
                    stem: chord.stem,
                    chordX: layout.xPosition(chord.xPosition),
                    noteheadWidth: layout.noteheadColumnWidth * glyphScale,
                    stemLength: layout.lineSpacing * engravingMetrics.defaultStemLength * glyphScale,
                    noteCentersByID: noteCenters(for: chordItems, layout: layout)
                ) else { continue }
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
        token: GrandStaffGlyphToken,
        stemEnd: CGPoint,
        scale: Double,
        in context: GraphicsContext,
        fadeScale: Double,
        layout: GrandStaffNotationViewportLayoutService.Layout
    ) {
        drawGlyph(
            token,
            baselineAt: stemEnd,
            centeredOnAdvance: false,
            scale: scale,
            color: .primary,
            opacity: 0.45 * fadeScale,
            in: context,
            layout: layout
        )
    }

    private func noteCenters(
        for items: [GrandStaffNotationItem],
        layout: GrandStaffNotationViewportLayoutService.Layout
    ) -> [String: CGPoint] {
        Dictionary(uniqueKeysWithValues: items.map { item in
            let scale = engravingMetrics.glyphScale(isGrace: item.isGrace)
            return (item.id, CGPoint(
                x: layout.xPosition(item.xPosition) + item.noteheadXOffset * layout.noteheadColumnWidth * scale,
                y: layout.yPosition(staffStep: item.staffStep, staffNumber: item.staffNumber)
            ))
        })
    }

    private func drawNoteHead(
        item: GrandStaffNotationItem,
        chordBaseX: CGFloat,
        x: CGFloat,
        y: CGFloat,
        in context: GraphicsContext,
        fadeScale: Double,
        layout: GrandStaffNotationViewportLayoutService.Layout
    ) {
        guard let noteheadToken = item.noteheadGlyphToken else { return }
        let baseOpacity: Double = item.isHighlighted ? 1.0 : 0.55
        let noteColor = resolvedNoteColor(for: item)
        drawGlyph(
            noteheadToken,
            baselineAt: CGPoint(x: x, y: y),
            centeredOnAdvance: true,
            scale: engravingMetrics.glyphScale(isGrace: item.isGrace),
            color: noteColor,
            opacity: baseOpacity * fadeScale,
            in: context,
            layout: layout
        )

        if let accidentalToken = item.displayedAccidental?.glyphToken,
           let accidentalXOffset = item.accidentalXOffsetStaffSpaces {
            let accidentalOpacity = min(1.0, 0.85 * fadeScale)
            drawGlyph(
                accidentalToken,
                baselineAt: CGPoint(x: chordBaseX + accidentalXOffset * layout.lineSpacing, y: y),
                centeredOnAdvance: true,
                scale: engravingMetrics.glyphScale(isGrace: item.isGrace),
                color: noteColor,
                opacity: accidentalOpacity,
                in: context,
                layout: layout
            )
        }

        if item.dotCount > 0,
           let dotXOffset = item.dotXOffsetStaffSpaces,
           let dotStaffStep = item.dotStaffStep {
            for dotIndex in 0 ..< item.dotCount {
                drawGlyph(
                    .augmentationDot,
                    baselineAt: CGPoint(
                        x: chordBaseX + (dotXOffset + Double(dotIndex) * engravingMetrics.dotSpacing)
                            * layout.lineSpacing,
                        y: layout.yPosition(staffStep: dotStaffStep, staffNumber: item.staffNumber)
                    ),
                    centeredOnAdvance: true,
                    scale: engravingMetrics.glyphScale(isGrace: item.isGrace),
                    color: noteColor,
                    opacity: baseOpacity * fadeScale,
                    in: context,
                    layout: layout
                )
            }
        }
    }

    private func drawGlyph(
        _ token: GrandStaffGlyphToken,
        baselineAt point: CGPoint,
        centeredOnAdvance: Bool,
        scale: Double,
        color: Color,
        opacity: Double,
        in context: GraphicsContext,
        layout: GrandStaffNotationViewportLayoutService.Layout
    ) {
        let text = Text(token.glyph)
            .font(.custom("Bravura", fixedSize: layout.smuflFontSize * scale))
            .foregroundStyle(color.opacity(opacity))
        let resolved = context.resolve(text)
        let proposal = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        let size = resolved.measure(in: proposal)
        let x = centeredOnAdvance ? point.x - size.width / 2 : point.x
        context.draw(
            resolved,
            at: CGPoint(x: x, y: point.y - resolved.firstBaseline(in: proposal)),
            anchor: .topLeading
        )
    }

    private func resolvedNoteColor(for item: GrandStaffNotationItem) -> Color {
        resolvedNotationColor(isHighlighted: item.isHighlighted, staffNumber: item.staffNumber)
    }

    private func resolvedNotationColor(isHighlighted: Bool, staffNumber: Int) -> Color {
        guard isHighlighted else { return .primary }
        return PianoGuideHighlightTintToken.resolve(
            staffNumber: staffNumber,
            keyKind: .white
        ).swiftUIColor
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

    private func strokeWidth(_ staffSpaces: Double, layout: GrandStaffNotationViewportLayoutService.Layout) -> CGFloat {
        max(1 / max(displayScale, 1), layout.lineSpacing * staffSpaces)
    }
}
