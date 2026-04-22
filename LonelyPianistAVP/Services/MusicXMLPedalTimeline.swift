import Foundation

struct MusicXMLPedalTimeline: Equatable, Sendable {
    struct Change: Equatable, Sendable {
        let tick: Int
        let isDown: Bool
    }

    private let changes: [Change]

    init(events: [MusicXMLPedalEvent]) {
        let normalized = events
            .compactMap { event -> Change? in
                guard let isDown = event.isDown else { return nil }
                return Change(tick: event.tick, isDown: isDown)
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
}

