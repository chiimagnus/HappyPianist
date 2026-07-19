import Foundation

struct GrandStaffHorizontalSpacingService {
    struct Anchor: Equatable {
        let tick: Int
        let position: Double
    }

    struct RhythmicColumn: Equatable {
        let tick: Int
        let durationTicks: Int
        let leftExtent: Double
        let rightExtent: Double
    }

    struct Layout: Equatable {
        let rhythmicPositionsByTick: [Int: Double]
        let barlinePositionsByTick: [Int: Double]
        let attributePositionsByTick: [Int: Double]
        private let rhythmicAnchors: [Anchor]

        init(
            rhythmicPositionsByTick: [Int: Double],
            barlinePositionsByTick: [Int: Double],
            attributePositionsByTick: [Int: Double],
            rhythmicAnchors: [Anchor]
        ) {
            self.rhythmicPositionsByTick = rhythmicPositionsByTick
            self.barlinePositionsByTick = barlinePositionsByTick
            self.attributePositionsByTick = attributePositionsByTick
            self.rhythmicAnchors = rhythmicAnchors
        }

        func position(at tick: Double) -> Double {
            guard let first = rhythmicAnchors.first, let last = rhythmicAnchors.last else { return 0 }
            if tick <= Double(first.tick) { return first.position }
            if tick >= Double(last.tick) { return last.position }
            var lowerIndex = 0
            var upperIndex = rhythmicAnchors.count - 1
            while lowerIndex < upperIndex {
                let middle = (lowerIndex + upperIndex) / 2
                if Double(rhythmicAnchors[middle].tick) < tick {
                    lowerIndex = middle + 1
                } else {
                    upperIndex = middle
                }
            }
            let upper = rhythmicAnchors[upperIndex]
            let lower = rhythmicAnchors[upperIndex - 1]
            let progress = (tick - Double(lower.tick)) / Double(max(1, upper.tick - lower.tick))
            return lower.position + (upper.position - lower.position) * progress
        }
    }

    private enum Kind: Int {
        case barline
        case attribute
        case rhythm
    }

    private struct Column {
        let tick: Int
        let kind: Kind
        let durationTicks: Int
        let leftExtent: Double
        let rightExtent: Double
    }

    private let minimumGap = 0.75
    private let barlineExtent = 0.12
    private let attributeExtent = 1.1

    func makeLayout(
        rhythmicColumns: [RhythmicColumn],
        barlineTicks: Set<Int> = [],
        attributeTicks: Set<Int> = [],
        barlineExtentsByTick: [Int: Double] = [:],
        attributeRightExtentsByTick: [Int: Double] = [:]
    ) -> Layout {
        let mergedRhythmicColumns = Dictionary(grouping: rhythmicColumns, by: \.tick).values.map { columns in
            RhythmicColumn(
                tick: columns[0].tick,
                durationTicks: max(1, columns.map(\.durationTicks).min() ?? 1),
                leftExtent: columns.map(\.leftExtent).max() ?? 0,
                rightExtent: columns.map(\.rightExtent).max() ?? 0
            )
        }
        let columns = (
            mergedRhythmicColumns.map {
                Column(
                    tick: $0.tick,
                    kind: .rhythm,
                    durationTicks: $0.durationTicks,
                    leftExtent: $0.leftExtent,
                    rightExtent: $0.rightExtent
                )
            } +
                barlineTicks.map {
                    Column(
                        tick: $0,
                        kind: .barline,
                        durationTicks: 0,
                        leftExtent: barlineExtentsByTick[$0] ?? barlineExtent,
                        rightExtent: barlineExtentsByTick[$0] ?? barlineExtent
                    )
                } +
                attributeTicks.map {
                    Column(
                        tick: $0,
                        kind: .attribute,
                        durationTicks: 0,
                        leftExtent: attributeExtent,
                        rightExtent: attributeRightExtentsByTick[$0] ?? attributeExtent
                    )
                }
        ).sorted {
            if $0.tick != $1.tick { return $0.tick < $1.tick }
            return $0.kind.rawValue < $1.kind.rawValue
        }

        var rhythmicPositionsByTick: [Int: Double] = [:]
        var barlinePositionsByTick: [Int: Double] = [:]
        var attributePositionsByTick: [Int: Double] = [:]
        var previous: (column: Column, position: Double)?

        for column in columns {
            let position: Double
            if let previous {
                let opticalDistance = previous.column.rightExtent + minimumGap + column.leftExtent
                let rhythmicDistance = column.kind == .rhythm && previous.column.kind == .rhythm
                    ? self.rhythmicDistance(durationTicks: previous.column.durationTicks)
                    : 0
                position = previous.position + max(opticalDistance, rhythmicDistance)
            } else {
                position = column.leftExtent
            }
            switch column.kind {
            case .rhythm: rhythmicPositionsByTick[column.tick] = position
            case .barline: barlinePositionsByTick[column.tick] = position
            case .attribute: attributePositionsByTick[column.tick] = position
            }
            previous = (column, position)
        }

        return Layout(
            rhythmicPositionsByTick: rhythmicPositionsByTick,
            barlinePositionsByTick: barlinePositionsByTick,
            attributePositionsByTick: attributePositionsByTick,
            rhythmicAnchors: rhythmicPositionsByTick.map { Anchor(tick: $0.key, position: $0.value) }
                .sorted { $0.tick < $1.tick }
        )
    }

    private func rhythmicDistance(durationTicks: Int) -> Double {
        let quarterRatio = Double(max(1, durationTicks)) / Double(MusicXMLTempoMap.ticksPerQuarter)
        return 3.4 * sqrt(quarterRatio)
    }
}
