import CoreGraphics
import MusicXML
import Practice

public struct GrandStaffNotationPageGeometry: Equatable, Sendable {
    public static let canonical = Self()
    public let width = 52.0
    public let height = 73.5
    public let margin = 3.0
    public let systemGap = 3.0
    public let gutter = 2.0
    let contentHeight = 61.5
    var contentWidth: Double { width - margin * 2 }
    public var spreadWidth: Double { width * 2 + gutter }
}

public struct GrandStaffNotationPagePlan: Equatable, Sendable {
    public struct Location: Equatable, Sendable {
        public let pageIndex: Int
        public let systemID: String
        public var spreadIndex: Int { pageIndex / 2 }
    }
    public struct Measure: Equatable, Sendable {
        public let span: MusicXMLMeasureSpan
        public let rect: CGRect
    }
    public struct Page: Equatable, Identifiable, Sendable {
        public let id: String
        public let index: Int
        public let measures: [Measure]
        let systems: [System]
    }
    struct System: Equatable, Identifiable, Sendable {
        let id: String
        let measures: [MusicXMLMeasureSpan]
        let xRange: ClosedRange<Double>
        let notation: GrandStaffNotationLayout
        let ink: CGRect
        let header: GrandStaffNotationSignatureLayout
        let scale: Double
        let rect: CGRect
        var musicWidth: Double { xRange.upperBound - xRange.lowerBound }
        var musicOriginX: Double { header.width - min(0, ink.minX) }
    }
    public let input: GrandStaffNotationScoreInput
    public let geometry: GrandStaffNotationPageGeometry
    public let pages: [Page]
    let score: GrandStaffNotationScoreLayout
    public var spreadCount: Int { (pages.count + 1) / 2 }

    public func navigationTick(forSpread index: Int, within range: Range<Int>? = nil) -> Int? {
        guard (0..<spreadCount).contains(index),
              let first = pages[index * 2].measures.first?.span,
              let last = pages[min(index * 2 + 1, pages.count - 1)].measures.last?.span else { return nil }
        let start = max(first.startTick, range?.lowerBound ?? first.startTick)
        let end = min(last.endTick, range?.upperBound ?? last.endTick)
        return start < end ? start : nil
    }

    public func pageIndex(containingTick tick: Int) -> Int? {
        location(containingTick: tick)?.pageIndex
    }
    public func location(containingTick tick: Int) -> Location? {
        guard let first = input.measureSpans.first, let last = input.measureSpans.last, first.startTick <= tick, tick <= last.endTick else { return nil }
        for page in pages {
            if let system = page.systems.first(where: { $0.measures.contains { $0.startTick <= tick && tick < $0.endTick || (tick == last.endTick && $0.occurrenceID == last.occurrenceID) } }) {
                return .init(pageIndex: page.index, systemID: system.id)
            }
        }
        return nil
    }
    public func spreadIndex(containingTick tick: Int) -> Int? { pageIndex(containingTick: tick).map { $0 / 2 } }
    public func spreadIndex(containing occurrence: PracticeMeasureOccurrenceID) -> Int? {
        location(containing: occurrence)?.spreadIndex
    }
    public func location(containing occurrence: PracticeMeasureOccurrenceID) -> Location? {
        for page in pages {
            if let system = page.systems.first(where: { $0.measures.contains { $0.occurrenceID == occurrence } }) {
                return .init(pageIndex: page.index, systemID: system.id)
            }
        }
        return nil
    }
}
