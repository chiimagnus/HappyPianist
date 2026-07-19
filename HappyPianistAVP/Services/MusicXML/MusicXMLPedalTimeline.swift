import Foundation

struct MusicXMLPedalTimeline: Equatable {
    struct Change: Equatable {
        let tick: Int
        let isDown: Bool
    }

    struct ControllerChange: Equatable, Sendable {
        let sourceDirectionID: MusicXMLDirectionSourceID?
        let performedOccurrenceIndex: Int
        let tick: Int
        let controllerNumber: UInt8
        let value: UInt8
    }

    private let changes: [Change]
    private let controllers: [ControllerChange]
    private let releaseEdgeTicks: [Int]

    init(events: [MusicXMLPedalEvent]) {
        let releaseEdges = Set(
            events.compactMap { event -> Int? in
                guard event.controller == .damper,
                      let value = event.value
                else { return nil }
                return value.isEngaged ? nil : event.tick
            }
        )
        releaseEdgeTicks = releaseEdges.sorted()
        controllers = events
            .enumerated()
            .compactMap { offset, event -> (offset: Int, change: ControllerChange)? in
                guard let value = event.value else { return nil }
                return (
                    offset,
                    ControllerChange(
                        sourceDirectionID: event.sourceID,
                        performedOccurrenceIndex: event.performedOccurrenceIndex,
                        tick: event.tick,
                        controllerNumber: event.controller.rawValue,
                        value: value.midiValue
                    )
                )
            }
            .sorted { lhs, rhs in
                if lhs.change.tick != rhs.change.tick { return lhs.change.tick < rhs.change.tick }
                if lhs.change.controllerNumber != rhs.change.controllerNumber {
                    return lhs.change.controllerNumber < rhs.change.controllerNumber
                }
                return lhs.offset < rhs.offset
            }
            .map(\.change)

        let normalized = events
            .compactMap { event -> Change? in
                guard event.controller == .damper,
                      let value = event.value
                else { return nil }
                return Change(tick: event.tick, isDown: value.isEngaged)
            }
            .sorted { lhs, rhs in
                if lhs.tick != rhs.tick { return lhs.tick < rhs.tick }
                if lhs.isDown != rhs.isDown { return lhs.isDown == false }
                return false
            }

        var output: [Change] = []
        output.reserveCapacity(normalized.count)

        var currentState = false
        var index = 0
        while index < normalized.count {
            let tick = normalized[index].tick

            while index < normalized.count, normalized[index].tick == tick {
                currentState = normalized[index].isDown
                index += 1
            }

            if output.last?.isDown != currentState {
                output.append(Change(tick: tick, isDown: currentState))
            }
        }

        changes = output
    }

    func isDown(atTick tick: Int) -> Bool {
        guard changes.isEmpty == false else { return false }
        if tick < changes[0].tick { return false }

        var low = 0
        var high = changes.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if changes[mid].tick <= tick {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return changes[low].isDown
    }

    func nextChange(afterTick tick: Int) -> Change? {
        guard changes.isEmpty == false else { return nil }

        var low = 0
        var high = changes.count
        while low < high {
            let mid = (low + high) / 2
            if changes[mid].tick <= tick {
                low = mid + 1
            } else {
                high = mid
            }
        }

        guard low < changes.count else { return nil }
        return changes[low]
    }

    func releaseEdges() -> [Int] {
        releaseEdgeTicks
    }

    func controllerChanges() -> [ControllerChange] {
        controllers
    }
}
