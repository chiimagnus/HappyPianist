import Foundation
@testable import HappyPianistAVP
import Synchronization

extension PerformanceMonotonicInstant {
    var date: Date {
        Date(timeIntervalSince1970: seconds)
    }
}

typealias TestMonotonicInstant = PerformanceMonotonicInstant

struct PerformanceReplayEvent<Payload> {
    let instant: TestMonotonicInstant
    let source: String
    let payload: Payload
}

struct PerformanceInputReplayCursor<Payload> {
    private let events: [PerformanceReplayEvent<Payload>]
    private(set) var index = 0

    init(events: [PerformanceReplayEvent<Payload>]) {
        self.events = events.enumerated().sorted { lhs, rhs in
            if lhs.element.instant != rhs.element.instant {
                return lhs.element.instant < rhs.element.instant
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    var hasNext: Bool {
        index < events.count
    }

    mutating func next() -> PerformanceReplayEvent<Payload>? {
        guard events.indices.contains(index) else { return nil }
        defer { index += 1 }
        return events[index]
    }

    mutating func replay(_ consume: (PerformanceReplayEvent<Payload>) throws -> Void) rethrows {
        while let event = next() {
            try consume(event)
        }
    }
}

final class DeterministicPerformanceClock: Sendable {
    private let instant: Mutex<TestMonotonicInstant>

    init(start: TestMonotonicInstant = TestMonotonicInstant(seconds: 0)) {
        instant = Mutex(start)
    }

    var now: TestMonotonicInstant {
        instant.withLock { $0 }
    }

    var performanceClock: PerformanceClock {
        PerformanceClock { [self] in now }
    }

    func advance(by interval: TimeInterval) {
        instant.withLock { $0 = $0.advanced(by: interval) }
    }
}
