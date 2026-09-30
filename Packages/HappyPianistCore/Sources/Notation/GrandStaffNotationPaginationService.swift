import CoreGraphics
import Foundation

struct GrandStaffNotationPaginationService {
    func makePlan(score: GrandStaffNotationScoreLayout, geometry: GrandStaffNotationPageGeometry = .canonical) throws -> GrandStaffNotationPagePlan {
        let measures = score.input.measureSpans
        guard !measures.isEmpty, Set(measures.map(\.occurrenceID)).count == measures.count,
              zip(measures, measures.dropFirst()).allSatisfy({ $0.endTick == $1.startTick })
        else { throw GrandStaffNotationScoreLayoutService.ScoreLayoutError.inconsistentSourceFacts }
        let chords = Dictionary(uniqueKeysWithValues: score.notation.chords.map { ($0.id, $0) })
        var forbidden: Set<Int> = []
        for beam in score.notation.beams {
            guard case let .source(_, members) = beam.provenance else { continue }
            let indices = members.compactMap { chords[$0]?.tick }.compactMap { tick in measures.firstIndex { $0.startTick <= tick && tick < $0.endTick } }
            if let first = indices.min(), let last = indices.max(), first < last { forbidden.formUnion((first + 1)...last) }
        }
        func system(_ range: Range<Int>) throws -> GrandStaffNotationPagePlan.System {
            try Task.checkCancellation()
            let spans = Array(measures[range])
            let first = measures[range.lowerBound]
            let last = measures[range.upperBound - 1]
            guard let lower = score.spacing.barlinePositionsByTick[first.startTick], let upper = score.spacing.barlinePositionsByTick[last.endTick], upper > lower else { throw GrandStaffNotationScoreLayoutService.ScoreLayoutError.inconsistentSourceFacts }
            let context = GrandStaffNotationContextResolver().context(input: score.input, tick: first.startTick)
            let header = GrandStaffNotationSignatureLayout.header(context)
            let notation = GrandStaffNotationSystemLayoutService().makeLayout(score: score, xRange: lower...upper, tickRange: first.startTick..<last.endTick, context: context, overlay: .empty)
            let absolute = notation.scaledHorizontally(by: upper - lower)
            let ink = GrandStaffNotationInkBoundsService().makeLayout(notation: absolute).bounds
            let combined = ink.union(header.bounds)
            let width = header.width + max(upper - lower, ink.maxX) - min(0, ink.minX)
            let height = combined.height + 0.4
            let scale = min(1, geometry.contentWidth / width, geometry.contentHeight / height)
            return .init(id: first.id + ":" + last.id, measures: spans, xRange: lower...upper, notation: notation, ink: ink, header: header, scale: scale, rect: CGRect(x: 0, y: combined.minY - 0.2, width: width, height: height))
        }
        var systems: [GrandStaffNotationPagePlan.System] = []
        var start = 0
        while start < measures.count {
            var end = start + 1
            while end < measures.count, forbidden.contains(end) { end += 1 }
            var selected = try system(start..<end)
            while end < measures.count {
                var next = end + 1
                while next < measures.count, forbidden.contains(next) { next += 1 }
                let candidate = try system(start..<next)
                guard candidate.rect.width <= geometry.contentWidth, candidate.rect.height <= geometry.contentHeight else { break }
                selected = candidate
                end = next
            }
            systems.append(selected)
            start = end
        }
        var pages: [GrandStaffNotationPagePlan.Page] = []
        var pageSystems: [GrandStaffNotationPagePlan.System] = []
        var occupied = 0.0
        func finishPage() {
            guard !pageSystems.isEmpty else { return }
            var rects: [GrandStaffNotationPagePlan.Measure] = []
            var top = geometry.margin + 3
            for system in pageSystems {
                for span in system.measures {
                    guard let start = score.spacing.barlinePositionsByTick[span.startTick], let end = score.spacing.barlinePositionsByTick[span.endTick] else { continue }
                    rects.append(.init(span: span, rect: CGRect(x: geometry.margin + (system.musicOriginX + start - system.xRange.lowerBound) * system.scale, y: top, width: (end - start) * system.scale, height: system.rect.height * system.scale)))
                }
                top += system.rect.height * system.scale + geometry.systemGap
            }
            pages.append(.init(id: pageSystems[0].id, index: pages.count, measures: rects, systems: pageSystems))
            pageSystems = []
            occupied = 0
        }
        for system in systems {
            let height = system.rect.height * system.scale
            if system.scale < 1 { finishPage() }
            if !pageSystems.isEmpty, occupied + geometry.systemGap + height > geometry.contentHeight { finishPage() }
            occupied += (pageSystems.isEmpty ? 0 : geometry.systemGap) + height
            pageSystems.append(system)
            if system.scale < 1 { finishPage() }
        }
        finishPage()
        return .init(input: score.input, geometry: geometry, pages: pages, score: score)
    }
}

extension GrandStaffNotationSignatureLayout {
    static func header(_ context: GrandStaffNotationContext) -> Self {
        let treble = make(staff: context.treble, staffNumber: 1, x: 0.8)
        let bass = make(staff: context.bass, staffNumber: 2, x: 0.8)
        let bounds = treble.bounds.union(bass.bounds).union(CGRect(x: 0, y: -4, width: 0.8, height: 12))
        return .init(glyphs: treble.glyphs + bass.glyphs, bounds: bounds, width: max(treble.width, bass.width) + 0.8, labels: treble.labels + bass.labels)
    }
}

extension GrandStaffNotationLayout {
    func scaledHorizontally(by width: Double) -> Self {
        func positioned<Value>(_ values: [Value], _ x: WritableKeyPath<Value, Double>) -> [Value] {
            values.map { value in var result = value; result[keyPath: x] *= width; return result }
        }
        func spans<Value>(_ values: [Value], _ start: WritableKeyPath<Value, Double>, _ end: WritableKeyPath<Value, Double>) -> [Value] {
            values.map { value in var result = value; result[keyPath: start] *= width; result[keyPath: end] *= width; return result }
        }
        return .init(items: positioned(items, \.xPosition), chords: positioned(chords, \.xPosition), rests: positioned(rests, \.xPosition), ties: spans(ties, \.startXPosition, \.endXPosition), slurs: spans(slurs, \.startXPosition, \.endXPosition), tuplets: spans(tuplets, \.startXPosition, \.endXPosition), barlines: positioned(barlines, \.xPosition), beams: beams, ledgerLines: positioned(ledgerLines, \.xPosition), marks: positioned(marks, \.xPosition), attributeChanges: positioned(attributeChanges, \.xPosition), context: context, spannerAnchors: spannerAnchors.mapValues { value in var result = value; result.xPosition *= width; return result })
    }
}
