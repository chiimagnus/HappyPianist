import MusicXML
import Practice

struct GrandStaffNotationSystemLayoutService {
    func makeLayout(
        score: GrandStaffNotationScoreLayout,
        xRange: ClosedRange<Double>,
        tickRange: Range<Int>? = nil,
        overscan: Double = 0,
        context: GrandStaffNotationContext?,
        overlay: ScoreNotationProjection.Overlay
    ) -> GrandStaffNotationLayout {
        let width = xRange.upperBound - xRange.lowerBound
        let visibleRange = (xRange.lowerBound - overscan * width)...(xRange.upperBound + overscan * width)
        let absolute = score.notation
        let highlightedIDs = Set(score.input.projection.performedOccurrences.compactMap {
            $0.performanceEventIDs.contains(where: overlay.activeEventIDs.contains) ? $0.id.description : nil
        })

        func positioned<Value>(_ values: [Value], x: WritableKeyPath<Value, Double>, tick: KeyPath<Value, Int>, useTickRange: Bool = true) -> [Value] {
            values.compactMap { value in
                guard visibleRange.contains(value[keyPath: x]),
                      !useTickRange || (tickRange?.contains(value[keyPath: tick]) ?? true)
                else { return nil }
                var result = value
                result[keyPath: x] = (value[keyPath: x] - xRange.lowerBound) / width
                return result
            }
        }
        let items = positioned(absolute.items, x: \.xPosition, tick: \.tick).map { item in
            var result = item
            result.isHighlighted = highlightedIDs.contains(item.occurrenceID)
            return result
        }
        let rests = positioned(absolute.rests, x: \.xPosition, tick: \.tick).map { rest in
            var result = rest
            result.isHighlighted = highlightedIDs.contains(rest.id)
            return result
        }
        let chordIDs = Set(items.compactMap(\.chordID))
        let chords = positioned(absolute.chords, x: \.xPosition, tick: \.tick).filter { chordIDs.contains($0.id) }
        let beams = absolute.beams.compactMap { beam -> GrandStaffNotationBeam? in
            let indexByID = Dictionary(uniqueKeysWithValues: beam.chordIDs.enumerated().map { ($0.element, $0.offset) })
            let segments = beam.segments.compactMap { segment -> GrandStaffNotationBeamSegment? in
                if segment.hookDirection != nil {
                    return chordIDs.contains(segment.startChordID) ? segment : nil
                }
                guard let start = indexByID[segment.startChordID], let end = indexByID[segment.endChordID] else { return nil }
                let visible = beam.chordIDs[min(start, end)...max(start, end)].filter(chordIDs.contains)
                guard let first = visible.first, let last = visible.last, first != last else { return nil }
                return GrandStaffNotationBeamSegment(level: segment.level, startChordID: first, endChordID: last, hookDirection: nil)
            }
            guard !segments.isEmpty else { return nil }
            return GrandStaffNotationBeam(
                provenance: beam.provenance, id: beam.id,
                chordIDs: beam.chordIDs.filter(chordIDs.contains), segments: segments
            )
        }

        func clipped<Value>(
            _ values: [Value],
            startX: WritableKeyPath<Value, Double>, endX: WritableKeyPath<Value, Double>,
            startTick: KeyPath<Value, Int>, endTick: KeyPath<Value, Int>,
            startID: WritableKeyPath<Value, String?>, endID: WritableKeyPath<Value, String?>,
            fromPrevious: WritableKeyPath<Value, Bool>, toNext: WritableKeyPath<Value, Bool>
        ) -> [Value] {
            values.compactMap { value in
                guard value[keyPath: startX] < visibleRange.upperBound,
                      value[keyPath: endX] >= visibleRange.lowerBound,
                      tickRange.map({ value[keyPath: startTick] < $0.upperBound && value[keyPath: endTick] >= $0.lowerBound }) ?? true
                else { return nil }
                var result = value
                result[keyPath: fromPrevious] = value[keyPath: fromPrevious] || value[keyPath: startX] < visibleRange.lowerBound
                    || (tickRange.map { value[keyPath: startTick] < $0.lowerBound } ?? false)
                result[keyPath: toNext] = value[keyPath: toNext] || value[keyPath: endX] >= visibleRange.upperBound
                    || (tickRange.map { value[keyPath: endTick] >= $0.upperBound } ?? false)
                if result[keyPath: fromPrevious] { result[keyPath: startID] = nil }
                if result[keyPath: toNext] { result[keyPath: endID] = nil }
                result[keyPath: startX] = (max(value[keyPath: startX], visibleRange.lowerBound) - xRange.lowerBound) / width
                result[keyPath: endX] = (min(value[keyPath: endX], visibleRange.upperBound) - xRange.lowerBound) / width
                return result
            }
        }
        let ties = clipped(absolute.ties, startX: \.startXPosition, endX: \.endXPosition, startTick: \.startTick, endTick: \.endTick, startID: \.startOccurrenceID, endID: \.endOccurrenceID, fromPrevious: \.continuesFromPrevious, toNext: \.continuesToNext)
        let slurs = clipped(absolute.slurs, startX: \.startXPosition, endX: \.endXPosition, startTick: \.startTick, endTick: \.endTick, startID: \.startOccurrenceID, endID: \.endOccurrenceID, fromPrevious: \.continuesFromPrevious, toNext: \.continuesToNext)
        let tuplets = clipped(absolute.tuplets, startX: \.startXPosition, endX: \.endXPosition, startTick: \.startTick, endTick: \.endTick, startID: \.startOccurrenceID, endID: \.endOccurrenceID, fromPrevious: \.continuesFromPrevious, toNext: \.continuesToNext)
        let marks = absolute.marks.filter { mark in
            guard let tickRange else { return true }
            switch mark.kind {
            case .endingStop, .endingDiscontinue, .repeatBackward:
                return tickRange.lowerBound < mark.tick && mark.tick <= tickRange.upperBound
            default:
                return tickRange.contains(mark.tick)
            }
        }
        return GrandStaffNotationLayout(
            items: items, chords: chords, rests: rests, ties: ties, slurs: slurs, tuplets: tuplets,
            barlines: absolute.barlines.compactMap { barline in
                guard visibleRange.contains(barline.xPosition),
                      tickRange.map({ $0.lowerBound <= barline.tick && barline.tick <= $0.upperBound }) ?? true
                else { return nil }
                var result = barline
                result.xPosition = (barline.xPosition - xRange.lowerBound) / width
                return result
            },
            beams: beams,
            ledgerLines: positioned(absolute.ledgerLines, x: \.xPosition, tick: \.tick),
            marks: positioned(marks, x: \.xPosition, tick: \.tick, useTickRange: false),
            attributeChanges: positioned(absolute.attributeChanges, x: \.xPosition, tick: \.tick),
            context: context
        )
    }
}
