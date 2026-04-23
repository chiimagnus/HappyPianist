import Foundation

struct MusicXMLSlurTimeline: Equatable {
    private struct Span: Equatable {
        let startTick: Int
        let endTick: Int
    }

    private let spans: [Span]

    init(events: [MusicXMLSlurEvent]) {
        let ordered = events.sorted { lhs, rhs in
            if lhs.tick != rhs.tick { return lhs.tick < rhs.tick }
            if lhs.kind != rhs.kind { return lhs.kind == .start }
            return false
        }

        struct Key: Hashable {
            let partID: String
            let staff: Int?
            let voice: Int?
            let numberToken: String
        }

        func key(for event: MusicXMLSlurEvent) -> Key {
            Key(
                partID: event.scope.partID,
                staff: event.scope.staff,
                voice: event.scope.voice,
                numberToken: event.numberToken ?? "1"
            )
        }

        var openStartTickByKey: [Key: Int] = [:]
        var built: [Span] = []
        built.reserveCapacity(ordered.count / 2)

        for event in ordered {
            let k = key(for: event)
            switch event.kind {
                case .start:
                    openStartTickByKey[k] = event.tick
                case .stop:
                    if let start = openStartTickByKey.removeValue(forKey: k) {
                        let end = max(start, event.tick)
                        built.append(Span(startTick: start, endTick: end))
                    }
            }
        }

        for start in openStartTickByKey.values {
            built.append(Span(startTick: start, endTick: Int.max))
        }

        spans = built.sorted { lhs, rhs in
            if lhs.startTick != rhs.startTick { return lhs.startTick < rhs.startTick }
            return lhs.endTick < rhs.endTick
        }
    }

    func isActive(atTick tick: Int) -> Bool {
        let t = max(0, tick)
        return spans.contains(where: { $0.startTick <= t && t <= $0.endTick })
    }
}
