import SwiftUI
import MusicXML
import Practice

struct GrandStaffNotationRenderer {
    private let displayScale: CGFloat
    private let activeTickRange: Range<Int>?
    private let engravingMetrics = GrandStaffEngravingMetrics()
    private let chordLayoutService = GrandStaffChordLayoutService()

    init(displayScale: CGFloat = 1, activeTickRange: Range<Int>? = nil) {
        self.displayScale = displayScale
        self.activeTickRange = activeTickRange
    }

    func draw(
        presentation: GrandStaffNotationPresentation,
        in context: GraphicsContext,
        displayScale: CGFloat
    ) {
        let renderer = GrandStaffNotationRenderer(
            displayScale: displayScale,
            activeTickRange: presentation.activeTickRange
        )
        renderer.drawInternal(presentation, in: context)
    }

    private func drawInternal(
        _ presentation: GrandStaffNotationPresentation,
        in context: GraphicsContext
    ) {
        let layout = presentation.canvasLayout
        let practiceHandMode = presentation.practiceHandMode
        let translatedContext = context
        drawGrandStaffLines(in: translatedContext, layout: layout)
        drawContext(in: translatedContext, layout: layout)
        drawBarlines(presentation.notationLayout.barlines, in: translatedContext, layout: layout)
        drawAttributeChanges(
            presentation.notationLayout,
            in: translatedContext,
            layout: layout
        )
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
        let itemsByID = presentation.notationLayout.spannerAnchors.merging(Dictionary(uniqueKeysWithValues: presentation.notationLayout.items.map { ($0.id, $0) })) { _, local in local }
        drawCurves(
            ties: presentation.notationLayout.ties,
            slurs: presentation.notationLayout.slurs,
            itemsByID: itemsByID,
            in: translatedContext,
            layout: layout
        )
        drawTuplets(
            presentation.notationLayout.tuplets,
            itemsByID: itemsByID,
            in: translatedContext,
            layout: layout
        )
        drawMarks(presentation.notationLayout.marks, in: translatedContext, layout: layout)
    }

    private func rangeContext(forTicks ticks: [Int], in context: GraphicsContext) -> GraphicsContext {
        guard let activeTickRange,
              let first = ticks.min(), let last = ticks.max(),
              last < activeTickRange.lowerBound || first >= activeTickRange.upperBound
        else { return context }
        var result = context
        result.opacity *= 0.35
        return result
    }

    private func drawGrandStaffLines(
        in context: GraphicsContext,
        layout: GrandStaffNotationSystemCanvasLayoutService.Layout
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

    private func drawContext(in context: GraphicsContext, layout: GrandStaffNotationSystemCanvasLayoutService.Layout) {
        drawGlyph(.brace, baselineAt: CGPoint(x: 0, y: layout.bassBottomLineY), centeredOnAdvance: false, scale: 12 / 3.988, color: .primary, opacity: 0.7, in: context, layout: layout)
        drawSignature(layout.header, in: context, layout: layout)
    }

    private func drawSignature(_ signature: GrandStaffNotationSignatureLayout, in context: GraphicsContext, layout: GrandStaffNotationSystemCanvasLayoutService.Layout, musicRelative: Bool = false) {
        for glyph in signature.glyphs {
            drawGlyph(glyph.token, baselineAt: CGPoint(x: (musicRelative ? layout.contentMinX : 0) + glyph.point.x * layout.lineSpacing, y: layout.trebleBottomLineY + glyph.point.y * layout.lineSpacing), centeredOnAdvance: false, scale: glyph.scale, color: .primary, opacity: 0.8, in: context, layout: layout)
        }
        for label in signature.labels {
            context.draw(Text(label.text).font(Font(engravingMetrics.textFont(size: label.size * layout.lineSpacing))), at: CGPoint(x: (musicRelative ? layout.contentMinX : 0) + label.point.x * layout.lineSpacing, y: layout.trebleBottomLineY + label.point.y * layout.lineSpacing), anchor: .leading)
        }
    }

    private func drawAttributeChanges(_ notation: GrandStaffNotationLayout, in context: GraphicsContext, layout: GrandStaffNotationSystemCanvasLayoutService.Layout) {
        for change in notation.attributeChanges {
            let signature = GrandStaffNotationSignatureLayout.inline(change, notation: notation, musicWidth: Double((layout.contentMaxX - layout.contentMinX) / layout.lineSpacing))
            drawSignature(signature, in: context, layout: layout, musicRelative: true)
        }
    }

    private func drawMarks(
        _ marks: [GrandStaffNotationMark],
        in context: GraphicsContext,
        layout: GrandStaffNotationSystemCanvasLayoutService.Layout
    ) {
        drawEndings(marks, in: context, layout: layout)
        for mark in marks {
            let context = rangeContext(forTicks: [mark.tick], in: context)
            switch mark.kind {
            case .repeatForward, .repeatBackward:
                drawRepeat(mark, in: context, layout: layout)
            case .endingStart, .endingStop, .endingDiscontinue:
                continue
            case let .arpeggio(token):
                guard let lowest = mark.minimumStaffStep, let highest = mark.maximumStaffStep else { continue }
                let lowerStaffNumber = mark.minimumStaffNumber ?? mark.staffNumber
                let upperStaffNumber = mark.maximumStaffNumber ?? mark.staffNumber
                let lowerY = layout.yPosition(staffStep: lowest, staffNumber: lowerStaffNumber)
                let upperY = layout.yPosition(staffStep: highest, staffNumber: upperStaffNumber)
                let nativeHeight = engravingMetrics.bounds(for: token)?.height ?? 5.5
                let requiredHeight = max(2.2, Double(abs(lowerY - upperY) / layout.lineSpacing) + 1)
                drawGlyph(
                    token,
                    baselineAt: CGPoint(
                        x: layout.xPosition(mark.xPosition) - layout.lineSpacing * 1.2,
                        y: lowerY + layout.lineSpacing * 0.5
                    ),
                    centeredOnAdvance: false,
                    scale: requiredHeight / nativeHeight,
                    color: .primary,
                    opacity: 0.65,
                    in: context,
                    layout: layout
                )
            case .pedalChange:
                let point = markPoint(mark, layout: layout)
                drawGlyph(
                    .keyboardPedalUp,
                    baselineAt: point,
                    centeredOnAdvance: false,
                    scale: 0.75,
                    color: .primary,
                    opacity: 0.65,
                    in: context,
                    layout: layout
                )
                drawGlyph(
                    .keyboardPedalPed,
                    baselineAt: CGPoint(x: point.x + layout.lineSpacing * 1.6, y: point.y),
                    centeredOnAdvance: false,
                    scale: 0.75,
                    color: .primary,
                    opacity: 0.65,
                    in: context,
                    layout: layout
                )
            default:
                drawOrdinaryMark(mark, in: context, layout: layout)
            }
        }
    }

    private func drawOrdinaryMark(
        _ mark: GrandStaffNotationMark,
        in context: GraphicsContext,
        layout: GrandStaffNotationSystemCanvasLayoutService.Layout
    ) {
        let point = markPoint(mark, layout: layout)
        if let token = mark.glyphToken {
            drawGlyph(
                token,
                baselineAt: point,
                centeredOnAdvance: mark.kind != .pedalStart && mark.kind != .pedalStop,
                scale: mark.kind == .pedalStart || mark.kind == .pedalStop ? 0.75 : 0.72,
                color: .primary,
                opacity: 0.68,
                in: context,
                layout: layout
            )
            return
        }
        guard let text = mark.text, text.isEmpty == false else { return }
        let size = layout.lineSpacing * (mark.kind == .dynamic ? 1.15 : 0.92)
        let rendered = Text(text).font(Font(engravingMetrics.textFont(size: size, bold: mark.kind == .dynamic, italic: mark.kind == .dynamic)))
        context.draw(
            rendered.foregroundStyle(Color.primary.opacity(0.72)),
            at: point,
            anchor: mark.kind == .tempo || mark.kind == .text ? .leading : .center
        )
    }

    private func markPoint(
        _ mark: GrandStaffNotationMark,
        layout: GrandStaffNotationSystemCanvasLayoutService.Layout
    ) -> CGPoint {
        let x = layout.xPosition(mark.xPosition)
        let levelOffset = CGFloat(mark.collisionLevel) * layout.lineSpacing * 1.35
        switch mark.placement {
        case .above:
            let base = mark.maximumStaffStep.map {
                layout.yPosition(staffStep: $0, staffNumber: mark.staffNumber) - layout.lineSpacing * 1.15
            } ?? ((mark.staffNumber >= 2 ? layout.bassTopLineY : layout.trebleTopLineY) - layout.lineSpacing * 4.2)
            return CGPoint(x: x, y: base - levelOffset)
        case .below:
            let base = mark.minimumStaffStep.map {
                layout.yPosition(staffStep: $0, staffNumber: mark.staffNumber) + layout.lineSpacing * 1.15
            } ?? ((mark.staffNumber >= 2 ? layout.bassBottomLineY : layout.trebleBottomLineY) + layout.lineSpacing * 2.2)
            return CGPoint(x: x, y: base + levelOffset)
        case .left:
            return CGPoint(x: x - layout.lineSpacing, y: layout.yPosition(staffStep: 4, staffNumber: mark.staffNumber))
        }
    }

    private func drawRepeat(
        _ mark: GrandStaffNotationMark,
        in context: GraphicsContext,
        layout: GrandStaffNotationSystemCanvasLayoutService.Layout
    ) {
        let x = alignedToPixel(layout.xPosition(mark.xPosition))
        let isForward = mark.kind == .repeatForward
        let thickX = x + (isForward ? -0.25 : 0.25) * layout.lineSpacing
        var line = Path()
        line.move(to: CGPoint(x: thickX, y: layout.trebleTopLineY))
        line.addLine(to: CGPoint(x: thickX, y: layout.bassBottomLineY))
        context.stroke(
            line,
            with: .color(Color.primary.opacity(0.55)),
            style: .init(lineWidth: strokeWidth(0.35, layout: layout))
        )
        let dotX = x + (isForward ? 0.55 : -0.55) * layout.lineSpacing
        for staffNumber in [1, 2] {
            for staffStep in [3, 5] {
                drawGlyph(
                    .augmentationDot,
                    baselineAt: CGPoint(
                        x: dotX,
                        y: layout.yPosition(staffStep: staffStep, staffNumber: staffNumber)
                    ),
                    centeredOnAdvance: true,
                    scale: 0.9,
                    color: .primary,
                    opacity: 0.6,
                    in: context,
                    layout: layout
                )
            }
        }
        if let text = mark.text {
            context.draw(
                Text(text).font(Font(engravingMetrics.textFont(size: layout.lineSpacing * 0.92))).foregroundStyle(Color.primary.opacity(0.65)),
                at: CGPoint(x: x, y: layout.trebleTopLineY - layout.lineSpacing * 1.3),
                anchor: .center
            )
        }
    }

    private func drawEndings(
        _ marks: [GrandStaffNotationMark],
        in context: GraphicsContext,
        layout: GrandStaffNotationSystemCanvasLayoutService.Layout
    ) {
        let endings = marks.filter {
            $0.kind == .endingStart || $0.kind == .endingStop || $0.kind == .endingDiscontinue
        }.sorted { $0.xPosition < $1.xPosition }
        for (index, mark) in endings.enumerated() where mark.kind == .endingStart {
            let startX = layout.xPosition(mark.xPosition)
            let next = endings.dropFirst(index + 1).first {
                $0.staffNumber == mark.staffNumber && ($0.kind == .endingStop || $0.kind == .endingDiscontinue)
            }
            let context = rangeContext(forTicks: [mark.tick, next?.tick ?? mark.tick], in: context)
            let endX = next.map { layout.xPosition($0.xPosition) } ?? layout.contentMaxX
            let y = layout.trebleTopLineY - layout.lineSpacing * (4.5 + CGFloat(mark.collisionLevel) * 1.35)
            var path = Path()
            path.move(to: CGPoint(x: startX, y: y + (mark.continuesFromPrevious ? 0 : layout.lineSpacing * 0.8)))
            path.addLine(to: CGPoint(x: startX, y: y))
            path.addLine(to: CGPoint(x: endX, y: y))
            if next?.kind == .endingStop {
                path.addLine(to: CGPoint(x: endX, y: y + layout.lineSpacing * 0.8))
            }
            context.stroke(
                path,
                with: .color(Color.primary.opacity(0.5)),
                style: .init(lineWidth: strokeWidth(0.10, layout: layout))
            )
            if let text = mark.text {
                context.draw(
                    Text(text).font(Font(engravingMetrics.textFont(size: layout.lineSpacing * 0.92, bold: true))).foregroundStyle(Color.primary.opacity(0.7)),
                    at: CGPoint(x: startX + layout.lineSpacing * 0.35, y: y + layout.lineSpacing * 0.15),
                    anchor: .topLeading
                )
            }
        }
    }

    private func drawBarlines(
        _ barlines: [GrandStaffNotationBarline],
        in context: GraphicsContext,
        layout: GrandStaffNotationSystemCanvasLayoutService.Layout
    ) {
        guard barlines.isEmpty == false else { return }

        let stroke = StrokeStyle(lineWidth: strokeWidth(0.13, layout: layout))
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
        layout: GrandStaffNotationSystemCanvasLayoutService.Layout
    ) {
        guard items.isEmpty == false else { return }

        for item in items {
            let context = rangeContext(forTicks: [item.tick], in: context)
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

    private func drawCurves(
        ties: [GrandStaffNotationTie],
        slurs: [GrandStaffNotationSlur],
        itemsByID: [String: GrandStaffNotationItem],
        in context: GraphicsContext,
        layout: GrandStaffNotationSystemCanvasLayoutService.Layout
    ) {
        for tie in ties {
            let context = rangeContext(forTicks: [tie.startTick, tie.endTick], in: context)
            let isAbove = resolvedIsAbove(placementToken: tie.placementToken, voice: tie.voice)
            drawCurve(
                startOccurrenceID: tie.startOccurrenceID,
                endOccurrenceID: tie.endOccurrenceID,
                startXPosition: tie.startXPosition,
                endXPosition: tie.endXPosition,
                staffNumber: tie.staffNumber,
                isAbove: isAbove,
                height: 0.65,
                itemsByID: itemsByID,
                in: context,
                layout: layout
            )
        }
        for slur in slurs {
            let context = rangeContext(forTicks: [slur.startTick, slur.endTick], in: context)
            let isAbove = resolvedIsAbove(placementToken: slur.placementToken, voice: slur.voice)
            drawCurve(
                startOccurrenceID: slur.startOccurrenceID,
                endOccurrenceID: slur.endOccurrenceID,
                startXPosition: slur.startXPosition,
                endXPosition: slur.endXPosition,
                staffNumber: slur.staffNumber,
                isAbove: isAbove,
                height: 1.4,
                itemsByID: itemsByID,
                in: context,
                layout: layout
            )
        }
    }

    private func drawCurve(
        startOccurrenceID: String?,
        endOccurrenceID: String?,
        startXPosition: Double,
        endXPosition: Double,
        staffNumber: Int,
        isAbove: Bool,
        height: Double,
        itemsByID: [String: GrandStaffNotationItem],
        in context: GraphicsContext,
        layout: GrandStaffNotationSystemCanvasLayoutService.Layout
    ) {
        var start = curveEndpoint(
            occurrenceID: startOccurrenceID,
            xPosition: startXPosition,
            staffNumber: staffNumber,
            isAbove: isAbove,
            itemsByID: itemsByID,
            layout: layout
        )
        var end = curveEndpoint(
            occurrenceID: endOccurrenceID,
            xPosition: endXPosition,
            staffNumber: staffNumber,
            isAbove: isAbove,
            itemsByID: itemsByID,
            layout: layout
        )
        if startOccurrenceID == nil { start.y = end.y }
        if endOccurrenceID == nil { end.y = start.y }
        guard end.x > start.x else { return }
        let controlY = (isAbove ? min(start.y, end.y) : max(start.y, end.y))
            + (isAbove ? -1 : 1) * layout.lineSpacing * height
        var path = Path()
        path.move(to: start)
        path.addQuadCurve(
            to: end,
            control: CGPoint(x: (start.x + end.x) / 2, y: controlY)
        )
        context.stroke(
            path,
            with: .color(Color.primary.opacity(0.42)),
            style: .init(lineWidth: strokeWidth(0.10, layout: layout), lineCap: .round)
        )
    }

    private func curveEndpoint(
        occurrenceID: String?,
        xPosition: Double,
        staffNumber: Int,
        isAbove: Bool,
        itemsByID: [String: GrandStaffNotationItem],
        layout: GrandStaffNotationSystemCanvasLayoutService.Layout
    ) -> CGPoint {
        guard let occurrenceID, let item = itemsByID[occurrenceID] else {
            return CGPoint(
                x: layout.xPosition(xPosition),
                y: layout.yPosition(staffStep: isAbove ? 8 : 0, staffNumber: staffNumber)
            )
        }
        let scale = engravingMetrics.glyphScale(isGrace: item.isGrace)
        return CGPoint(
            x: layout.xPosition(xPosition) + item.noteheadXOffset * layout.noteheadColumnWidth * scale,
            y: layout.yPosition(staffStep: item.staffStep, staffNumber: item.staffNumber)
                + (isAbove ? -0.45 : 0.45) * layout.lineSpacing
        )
    }

    private func drawTuplets(
        _ tuplets: [GrandStaffNotationTuplet],
        itemsByID: [String: GrandStaffNotationItem],
        in context: GraphicsContext,
        layout: GrandStaffNotationSystemCanvasLayoutService.Layout
    ) {
        for tuplet in tuplets {
            let context = rangeContext(forTicks: [tuplet.startTick, tuplet.endTick], in: context)
            let isAbove = resolvedIsAbove(placementToken: tuplet.placementToken, voice: tuplet.voice)
            let start = curveEndpoint(
                occurrenceID: tuplet.startOccurrenceID,
                xPosition: tuplet.startXPosition,
                staffNumber: tuplet.staffNumber,
                isAbove: isAbove,
                itemsByID: itemsByID,
                layout: layout
            )
            let end = curveEndpoint(
                occurrenceID: tuplet.endOccurrenceID,
                xPosition: tuplet.endXPosition,
                staffNumber: tuplet.staffNumber,
                isAbove: isAbove,
                itemsByID: itemsByID,
                layout: layout
            )
            guard end.x > start.x else { continue }
            let outwardY = (isAbove ? min(start.y, end.y) : max(start.y, end.y))
                + (isAbove ? -1 : 1) * layout.lineSpacing * Double(1 + tuplet.nestingLevel)
            let centerX = (start.x + end.x) / 2
            let numberGap = tuplet.displayNumber == nil ? 0 : layout.lineSpacing * 0.8

            if tuplet.bracketToken?.lowercased() != "no" {
                var bracket = Path()
                bracket.move(to: CGPoint(x: start.x, y: outwardY))
                bracket.addLine(to: CGPoint(x: centerX - numberGap, y: outwardY))
                bracket.move(to: CGPoint(x: centerX + numberGap, y: outwardY))
                bracket.addLine(to: CGPoint(x: end.x, y: outwardY))
                if tuplet.continuesFromPrevious == false {
                    bracket.move(to: CGPoint(x: start.x, y: outwardY))
                    bracket.addLine(to: CGPoint(x: start.x, y: outwardY + (isAbove ? 0.45 : -0.45) * layout.lineSpacing))
                }
                if tuplet.continuesToNext == false {
                    bracket.move(to: CGPoint(x: end.x, y: outwardY))
                    bracket.addLine(to: CGPoint(x: end.x, y: outwardY + (isAbove ? 0.45 : -0.45) * layout.lineSpacing))
                }
                context.stroke(
                    bracket,
                    with: .color(Color.primary.opacity(0.42)),
                    style: .init(lineWidth: strokeWidth(0.10, layout: layout))
                )
            }

            if let displayNumber = tuplet.displayNumber {
                context.draw(
                    Text(displayNumber, format: .number)
                        .font(Font(engravingMetrics.textFont(size: layout.lineSpacing * 1.1, bold: true)))
                        .foregroundStyle(Color.primary.opacity(0.7)),
                    at: CGPoint(x: centerX, y: outwardY),
                    anchor: .center
                )
            }
        }
    }

    private func resolvedIsAbove(placementToken: String?, voice: Int) -> Bool {
        switch placementToken?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "above": true
        case "below": false
        default: voice.isMultiple(of: 2) == false
        }
    }

    private func drawLedgerLines(
        _ ledgerLines: [GrandStaffNotationLedgerLine],
        in context: GraphicsContext,
        layout: GrandStaffNotationSystemCanvasLayoutService.Layout
    ) {
        for ledgerLine in ledgerLines {
            let context = rangeContext(forTicks: [ledgerLine.tick], in: context)
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
        layout: GrandStaffNotationSystemCanvasLayoutService.Layout
    ) {
        for rest in rests {
            let context = rangeContext(forTicks: [rest.tick], in: context)
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
               let dotBounds = engravingMetrics.bounds(for: .augmentationDot)
            {
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
        layout: GrandStaffNotationSystemCanvasLayoutService.Layout
    ) {
        let stemStroke = StrokeStyle(
            lineWidth: strokeWidth(engravingMetrics.stemThickness, layout: layout),
            lineCap: .round
        )

        for chord in chords {
            let context = rangeContext(forTicks: [chord.tick], in: context)
            if beamedChordIDs.contains(chord.id) { continue }
            guard chord.noteType.grandStaffHasStem, chord.stem.isVisible else { continue }
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

            if let flagToken = chord.noteType.grandStaffFlagGlyphToken(stemDirection: chord.stem.direction) {
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
        layout: GrandStaffNotationSystemCanvasLayoutService.Layout
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
        for beam in beams {
            let chords = beam.chordIDs.compactMap { chordsByID[$0] }
            let context = rangeContext(forTicks: chords.map(\.tick), in: context)
            guard let geometry = chordLayoutService.beamGeometry(
                beam: beam, chords: chords, itemsByChordID: itemsByChordID,
                lineSpacing: layout.lineSpacing,
                chordX: { layout.xPosition($0.xPosition) },
                noteCenters: { noteCenters(for: $0, layout: layout) }
            ) else { continue }
            let fadeScale = chords.compactMap { itemsByChordID[$0.id] }
                .map { chordFadeScale(for: $0, practiceHandMode: practiceHandMode) }.max() ?? 1
            for segment in geometry.segments {
                var path = Path()
                path.move(to: segment.start)
                path.addLine(to: segment.end)
                context.stroke(path, with: .color(Color.primary.opacity(0.42 * fadeScale)), style: beamStroke)
            }
            for chord in chords {
                guard let stem = geometry.stemsByChordID[chord.id] else { continue }
                var path = Path()
                path.move(to: stem.start)
                path.addLine(to: stem.end)
                let chordScale = itemsByChordID[chord.id].map { chordFadeScale(for: $0, practiceHandMode: practiceHandMode) } ?? 1
                context.stroke(path, with: .color(Color.primary.opacity(0.45 * chordScale)), style: stemStroke)
            }
        }
    }

    private func drawFlag(
        token: GrandStaffGlyphToken,
        stemEnd: CGPoint,
        scale: Double,
        in context: GraphicsContext,
        fadeScale: Double,
        layout: GrandStaffNotationSystemCanvasLayoutService.Layout
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
        layout: GrandStaffNotationSystemCanvasLayoutService.Layout
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
        layout: GrandStaffNotationSystemCanvasLayoutService.Layout
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
           let accidentalXOffset = item.accidentalXOffsetStaffSpaces
        {
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
           let dotStaffStep = item.dotStaffStep
        {
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
        layout: GrandStaffNotationSystemCanvasLayoutService.Layout
    ) {
        let text = Text(token.glyph)
            .font(.custom("Bravura", fixedSize: layout.smuflFontSize * scale))
            .foregroundStyle(color.opacity(opacity))
        let resolved = context.resolve(text)
        let proposal = CGSize(
            width: max(1, layout.size.width),
            height: max(1, layout.size.height)
        )
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
        return staffNumber >= 2 ? .cyan : .yellow
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

    private func strokeWidth(_ staffSpaces: Double, layout: GrandStaffNotationSystemCanvasLayoutService.Layout) -> CGFloat {
        layout.lineSpacing * staffSpaces
    }
}
