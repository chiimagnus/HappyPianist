import Foundation
@testable import HappyPianistAVP
import Synchronization

enum PerformanceObservationReplayFixtureError: Error, Equatable {
    case unsupportedSchemaVersion(Int)
}

struct PerformanceObservationReplayFixture: Decodable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let observations: [PerformanceObservation]
    let legacyTake: RecordingTake

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw PerformanceObservationReplayFixtureError.unsupportedSchemaVersion(schemaVersion)
        }
        observations = try container.decode([PerformanceObservation].self, forKey: .observations)
        legacyTake = try container.decode(RecordingTake.self, forKey: .legacyTake)
    }

    var replayEvents: [PerformanceReplayEvent<PerformanceObservation>] {
        observations.map { observation in
            PerformanceReplayEvent(
                instant: observation.timing.correctedHost,
                source: observation.source.id,
                payload: observation
            )
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case observations
        case legacyTake
    }
}

struct PerformanceObservationReplayFixtureLoader {
    func load(filePath: StaticString = #filePath) throws -> PerformanceObservationReplayFixture {
        let data = try Data(contentsOf: testFixtureURL(
            "PerformanceObservationReplays.json",
            filePath: filePath
        ))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PerformanceObservationReplayFixture.self, from: data)
    }
}

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
