import CoreGraphics
import CoreText
import Foundation

struct GrandStaffNotationInkLayout: Equatable, Sendable {
    let bounds: CGRect
    let boundsByElementID: [String: CGRect]
}

struct GrandStaffNotationInkBoundsService {
    private let metrics = GrandStaffEngravingMetrics()
    private let chordService = GrandStaffChordLayoutService()

    func makeLayout(notation: GrandStaffNotationLayout, staffDistance: Double = 8) -> GrandStaffNotationInkLayout {
        var rectangles: [String: CGRect] = [:]
        func add(_ id: String, _ rect: CGRect) {
            rectangles[id] = (rectangles[id] ?? .null).union(rect)
        }
        func y(_ step: Int, _ staff: Int) -> Double {
            (staff == 2 ? staffDistance : 0) - Double(step) / 2
        }
        func glyph(_ id: String, _ token: GrandStaffGlyphToken, _ point: CGPoint, scale: Double = 1) {
            guard let bounds = metrics.bounds(for: token) else { return }
            add(id, CGRect(
                x: point.x + bounds.minX * scale, y: point.y - bounds.maxY * scale,
                width: bounds.width * scale, height: bounds.height * scale
            ))
        }
        func line(_ id: String, _ start: CGPoint, _ end: CGPoint, thickness: Double) {
            add(id, CGRect(
                x: min(start.x, end.x), y: min(start.y, end.y),
                width: abs(end.x - start.x), height: abs(end.y - start.y)
            ).insetBy(dx: -thickness / 2, dy: -thickness / 2))
        }
        func text(_ id: String, _ value: String, _ point: CGPoint, size: Double, leading: Bool = false, bold: Bool = false) {
            let base = CTFontCreateUIFontForLanguage(.system, size, nil)
                ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
            let font = bold ? CTFontCreateCopyWithSymbolicTraits(base, size, nil, .traitBold, .traitBold) ?? base : base
            let attributed = NSAttributedString(string: value, attributes: [.init(kCTFontAttributeName as String): font])
            let shaped = CTLineCreateWithAttributedString(attributed)
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leadingHeight: CGFloat = 0
            let width = CTLineGetTypographicBounds(shaped, &ascent, &descent, &leadingHeight)
            let height = ascent + descent + leadingHeight
            add(id, CGRect(x: point.x - (leading ? 0 : width / 2), y: point.y - height / 2, width: width, height: height))
        }
        func center(_ item: GrandStaffNotationItem) -> CGPoint {
            let scale = metrics.glyphScale(isGrace: item.isGrace)
            return CGPoint(
                x: item.xPosition + item.noteheadXOffset * metrics.noteheadColumnWidth * scale,
                y: y(item.staffStep, item.staffNumber)
            )
        }
        let itemsByID = notation.spannerAnchors.merging(Dictionary(uniqueKeysWithValues: notation.items.map { ($0.id, $0) })) { _, local in local }
        let itemsByChord = Dictionary(grouping: notation.items, by: { $0.chordID ?? "" })
        let chordsByID = Dictionary(uniqueKeysWithValues: notation.chords.map { ($0.id, $0) })
        let beamed = Set(notation.beams.flatMap(\.chordIDs))
        for item in notation.items {
            let point = center(item)
            let scale = metrics.glyphScale(isGrace: item.isGrace)
            add(item.id, CGRect(x: point.x - 0.78, y: point.y - 0.78, width: 1.56, height: 1.56))
            if let token = item.noteheadGlyphToken { glyph(item.id, token, point, scale: scale) }
            if let token = item.displayedAccidental?.glyphToken, let offset = item.accidentalXOffsetStaffSpaces {
                glyph(item.id, token, CGPoint(x: item.xPosition + offset, y: point.y), scale: scale)
            }
            if let offset = item.dotXOffsetStaffSpaces, let step = item.dotStaffStep {
                for index in 0..<item.dotCount {
                    glyph(item.id, .augmentationDot, CGPoint(
                        x: item.xPosition + offset + Double(index) * metrics.dotSpacing,
                        y: y(step, item.staffNumber)
                    ), scale: scale)
                }
            }
        }
        for rest in notation.rests {
            guard let token = rest.glyphToken else { continue }
            add(rest.id, CGRect(x: rest.xPosition - 0.78, y: y(rest.staffStep, rest.staffNumber) - 0.78, width: 1.56, height: 1.56))
            glyph(rest.id, token, CGPoint(x: rest.xPosition, y: y(rest.staffStep, rest.staffNumber)))
            if let bounds = metrics.bounds(for: token), let dot = metrics.bounds(for: .augmentationDot) {
                for index in 0..<rest.dotCount {
                    glyph(rest.id, .augmentationDot, CGPoint(
                        x: rest.xPosition + bounds.maxX + metrics.dotNoteheadGap - dot.minX + Double(index) * metrics.dotSpacing,
                        y: y(rest.staffStep + 1, rest.staffNumber)
                    ))
                }
            }
        }
        for ledger in notation.ledgerLines {
            line(ledger.id,
                 CGPoint(x: ledger.xPosition + ledger.minXOffsetStaffSpaces, y: y(ledger.staffStep, ledger.staffNumber)),
                 CGPoint(x: ledger.xPosition + ledger.maxXOffsetStaffSpaces, y: y(ledger.staffStep, ledger.staffNumber)),
                 thickness: metrics.ledgerLineThickness)
        }
        for chord in notation.chords where !beamed.contains(chord.id) {
            guard chord.stem.isVisible, chord.noteType.grandStaffHasStem,
                  let items = itemsByChord[chord.id], !items.isEmpty else { continue }
            let scale = metrics.glyphScale(isGrace: items.allSatisfy(\.isGrace))
            guard let stem = chordService.stemGeometry(
                stem: chord.stem, chordX: chord.xPosition,
                noteheadWidth: metrics.noteheadColumnWidth * scale, stemLength: metrics.defaultStemLength * scale,
                noteCentersByID: Dictionary(uniqueKeysWithValues: items.map { ($0.id, center($0)) })
            ) else { continue }
            line(chord.id, stem.start, stem.end, thickness: metrics.stemThickness)
            if let token = chord.noteType.grandStaffFlagGlyphToken(stemDirection: chord.stem.direction) {
                glyph(chord.id, token, stem.end, scale: scale)
            }
        }
        for beam in notation.beams {
            guard let geometry = chordService.beamGeometry(
                beam: beam, chords: beam.chordIDs.compactMap { chordsByID[$0] }, itemsByChordID: itemsByChord,
                lineSpacing: 1, chordX: { CGFloat($0.xPosition) },
                noteCenters: { items in Dictionary(uniqueKeysWithValues: items.map { ($0.id, center($0)) }) }
            ) else { continue }
            for stem in geometry.stemsByChordID.values {
                line(beam.id, stem.start, stem.end, thickness: metrics.stemThickness)
            }
            for segment in geometry.segments {
                line(beam.id, segment.start, segment.end, thickness: metrics.beamThickness)
            }
        }
        func isAbove(_ placement: String?, _ voice: Int) -> Bool {
            switch placement?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "above": true
            case "below": false
            default: !voice.isMultiple(of: 2)
            }
        }
        func endpoint(_ id: String?, _ x: Double, _ staff: Int, _ above: Bool) -> CGPoint {
            guard let id, let item = itemsByID[id] else {
                return CGPoint(x: x, y: y(above ? 8 : 0, staff))
            }
            let point = center(item)
            return CGPoint(x: x + item.noteheadXOffset * metrics.noteheadColumnWidth, y: point.y + (above ? -0.45 : 0.45))
        }
        func curve(_ id: String, _ startID: String?, _ endID: String?, _ startX: Double, _ endX: Double,
                   _ staff: Int, _ above: Bool, _ height: Double) {
            var start = endpoint(startID, startX, staff, above)
            var end = endpoint(endID, endX, staff, above)
            if startID == nil { start.y = end.y }
            if endID == nil { end.y = start.y }
            guard end.x > start.x else { return }
            let controlY = (above ? min(start.y, end.y) : max(start.y, end.y)) + (above ? -height : height)
            line(id, start, CGPoint(x: (start.x + end.x) / 2, y: controlY), thickness: 0.1)
            line(id, CGPoint(x: (start.x + end.x) / 2, y: controlY), end, thickness: 0.1)
        }
        for tie in notation.ties {
            curve(tie.id, tie.startOccurrenceID, tie.endOccurrenceID, tie.startXPosition, tie.endXPosition,
                  tie.staffNumber, isAbove(tie.placementToken, tie.voice), 0.65)
        }
        for slur in notation.slurs {
            curve(slur.id, slur.startOccurrenceID, slur.endOccurrenceID, slur.startXPosition, slur.endXPosition,
                  slur.staffNumber, isAbove(slur.placementToken, slur.voice), 1.4)
        }
        for tuplet in notation.tuplets {
            let above = isAbove(tuplet.placementToken, tuplet.voice)
            let start = endpoint(tuplet.startOccurrenceID, tuplet.startXPosition, tuplet.staffNumber, above)
            let end = endpoint(tuplet.endOccurrenceID, tuplet.endXPosition, tuplet.staffNumber, above)
            guard end.x > start.x else { continue }
            let outward = (above ? min(start.y, end.y) : max(start.y, end.y))
                + (above ? -1 : 1) * Double(1 + tuplet.nestingLevel)
            if tuplet.bracketToken?.lowercased() != "no" {
                line(tuplet.id, CGPoint(x: start.x, y: outward), CGPoint(x: end.x, y: outward), thickness: 0.1)
                line(tuplet.id, CGPoint(x: start.x, y: outward), CGPoint(x: end.x, y: outward + (above ? 0.45 : -0.45)), thickness: 0.1)
            }
            if let number = tuplet.displayNumber {
                text(tuplet.id, number.formatted(), CGPoint(x: (start.x + end.x) / 2, y: outward), size: 1.1, bold: true)
            }
        }
        for bar in notation.barlines {
            line(bar.id, CGPoint(x: bar.xPosition, y: -4), CGPoint(x: bar.xPosition, y: staffDistance), thickness: 0.13)
        }
        let endings = notation.marks.filter {
            $0.kind == .endingStart || $0.kind == .endingStop || $0.kind == .endingDiscontinue
        }.sorted { $0.xPosition < $1.xPosition }
        for mark in notation.marks {
            let baseline = mark.staffNumber == 2 ? staffDistance : 0
            let level = Double(mark.collisionLevel) * 1.35
            let point: CGPoint
            switch mark.placement {
            case .above: point = CGPoint(x: mark.xPosition, y: (mark.maximumStaffStep.map { y($0, mark.staffNumber) - 1.15 } ?? baseline - 8.2) - level)
            case .below: point = CGPoint(x: mark.xPosition, y: (mark.minimumStaffStep.map { y($0, mark.staffNumber) + 1.15 } ?? baseline + 2.2) + level)
            case .left: point = CGPoint(x: mark.xPosition - 1, y: y(4, mark.staffNumber))
            }
            switch mark.kind {
            case .repeatForward, .repeatBackward:
                add(mark.id, CGRect(x: mark.xPosition - 0.8, y: -4, width: 1.6, height: staffDistance + 4))
                if let value = mark.text { text(mark.id, value, CGPoint(x: mark.xPosition, y: -5.3), size: 0.92) }
            case .endingStart:
                let end = endings.first { $0.staffNumber == mark.staffNumber && $0.xPosition > mark.xPosition && ($0.kind == .endingStop || $0.kind == .endingDiscontinue) }?.xPosition
                    ?? notation.barlines.map(\.xPosition).max() ?? mark.xPosition
                let top = -8.5 - level
                line(mark.id, CGPoint(x: mark.xPosition, y: top), CGPoint(x: end, y: top + 0.8), thickness: 0.1)
                if let value = mark.text { text(mark.id, value, CGPoint(x: mark.xPosition + 0.35, y: top + 0.65), size: 0.92, leading: true, bold: true) }
            case .endingStop, .endingDiscontinue: break
            case let .arpeggio(token):
                guard let minimum = mark.minimumStaffStep, let maximum = mark.maximumStaffStep else { continue }
                let lower = y(minimum, mark.minimumStaffNumber ?? mark.staffNumber)
                let upper = y(maximum, mark.maximumStaffNumber ?? mark.staffNumber)
                let native = metrics.bounds(for: token)?.height ?? 5.5
                glyph(mark.id, token, CGPoint(x: mark.xPosition - 1.2, y: lower + 0.5), scale: max(2.2, abs(lower - upper) + 1) / native)
            case .pedalChange:
                glyph(mark.id, .keyboardPedalUp, point, scale: 0.75)
                glyph(mark.id, .keyboardPedalPed, CGPoint(x: point.x + 1.6, y: point.y), scale: 0.75)
            default:
                if let token = mark.glyphToken {
                    glyph(mark.id, token, point, scale: mark.kind == .pedalStart || mark.kind == .pedalStop ? 0.75 : 0.72)
                } else if let value = mark.text {
                    text(mark.id, value, point, size: mark.kind == .dynamic ? 1.15 : 0.92,
                         leading: mark.kind == .tempo || mark.kind == .text, bold: mark.kind == .dynamic)
                }
            }
        }
        for change in notation.attributeChanges {
            let signature = GrandStaffNotationSignatureLayout.inline(change, notation: notation, musicWidth: 1)
            if !signature.bounds.isNull { add(change.id, signature.bounds) }
        }
        let minX = notation.barlines.map(\.xPosition).min() ?? 0
        let maxX = notation.barlines.map(\.xPosition).max() ?? minX
        let staffBounds = CGRect(x: minX, y: -4.065, width: maxX - minX, height: staffDistance + 4.13)
        return GrandStaffNotationInkLayout(
            bounds: rectangles.values.reduce(staffBounds) { $0.union($1) }.insetBy(dx: -0.05, dy: -0.05), boundsByElementID: rectangles
        )
    }

}
