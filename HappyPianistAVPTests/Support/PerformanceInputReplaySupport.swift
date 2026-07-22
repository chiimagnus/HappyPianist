import Foundation
@testable import HappyPianistAVP
import simd
import Synchronization

enum PerformanceObservationReplayFixtureError: Error, Equatable {
    case unsupportedSchemaVersion(Int)
}

struct PerformanceObservationReplayFixture: Decodable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let observations: [PerformanceObservation]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw PerformanceObservationReplayFixtureError.unsupportedSchemaVersion(schemaVersion)
        }
        observations = try container.decode([PerformanceObservation].self, forKey: .observations)
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

enum PerformanceAlignmentReplayCorpusError: Error, Equatable {
    case unsupportedSchemaVersion(Int)
}

struct PerformanceAlignmentReplayCorpus: Decodable {
    struct ReplayCase: Decodable {
        struct Note: Decodable {
            let sourceOrdinal: Int
            let occurrenceIndex: Int
            let midiNote: Int
            let onTick: Int
        }

        struct Observation: Decodable {
            enum Kind: String, Decodable {
                case noteOn
                case pedal
            }

            let kind: Kind
            let midiNote: Int?
            let seconds: TimeInterval
            let value: Int?
        }

        struct Expected: Decodable {
            let aligned: Int
            let missing: Int
            let extra: Int
            let ambiguous: Int
            let controllerLinks: Int
            let requiresEarly: Bool
            let requiresLate: Bool
            let requiresChordSpread: Bool
            let performedOccurrences: [Int]
        }

        let id: String
        let coverage: [String]
        let notes: [Note]
        let observations: [Observation]
        let expected: Expected
    }

    static let currentSchemaVersion = 1

    let cases: [ReplayCase]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw PerformanceAlignmentReplayCorpusError.unsupportedSchemaVersion(schemaVersion)
        }
        cases = try container.decode([ReplayCase].self, forKey: .cases)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case cases
    }
}

struct PerformanceAlignmentReplayCorpusLoader {
    func load(filePath: StaticString = #filePath) throws -> PerformanceAlignmentReplayCorpus {
        let data = try Data(contentsOf: testFixtureURL(
            "PerformanceAlignmentReplays.json",
            filePath: filePath
        ))
        return try JSONDecoder().decode(PerformanceAlignmentReplayCorpus.self, from: data)
    }
}

enum SyntheticHandContactTraceFixtureError: Error, Equatable {
    case unsupportedSchemaVersion(Int)
    case missingKey(Int)
    case invalidWorldPosition
}

struct SyntheticHandContactTraceFixture: Decodable {
    static let currentSchemaVersion = 1

    let calibration: PianoTouchCalibration
    let traces: [SyntheticHandContactTrace]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw SyntheticHandContactTraceFixtureError.unsupportedSchemaVersion(schemaVersion)
        }
        calibration = try container.decode(PianoTouchCalibration.self, forKey: .calibration)
        traces = try container.decode([SyntheticHandContactTrace].self, forKey: .traces)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case calibration
        case traces
    }
}

struct SyntheticHandContactTrace: Decodable {
    let id: String
    let frames: [SyntheticHandContactFrame]
}

struct SyntheticHandContactFrame: Decodable {
    let seconds: TimeInterval
    private let fingers: [SyntheticFingerSample]
    private let palms: [SyntheticPalmSample]

    func snapshot(keyboardGeometry: PianoKeyboardGeometry) throws -> FingerTipsSnapshot {
        var snapshot = FingerTipsSnapshot.empty
        for sample in fingers {
            var handTips = snapshot[sample.hand.model]
            handTips[sample.finger.model] = try sample.position(keyboardGeometry: keyboardGeometry)
            snapshot[sample.hand.model] = handTips
        }
        for sample in palms {
            var handTips = snapshot[sample.hand.model]
            handTips.palm = try sample.position(keyboardGeometry: keyboardGeometry)
            snapshot[sample.hand.model] = handTips
        }
        return snapshot
    }

    private enum CodingKeys: String, CodingKey {
        case seconds
        case fingers
        case palms
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        seconds = try container.decode(TimeInterval.self, forKey: .seconds)
        fingers = try container.decodeIfPresent([SyntheticFingerSample].self, forKey: .fingers) ?? []
        palms = try container.decodeIfPresent([SyntheticPalmSample].self, forKey: .palms) ?? []
    }
}

struct SyntheticHandContactTraceFixtureLoader {
    func load(filePath: StaticString = #filePath) throws -> SyntheticHandContactTraceFixture {
        let data = try Data(contentsOf: testFixtureURL(
            "SyntheticHandContactTraces.json",
            filePath: filePath
        ))
        return try JSONDecoder().decode(SyntheticHandContactTraceFixture.self, from: data)
    }
}

private struct SyntheticFingerSample: Decodable {
    let hand: SyntheticTrackedHand
    let finger: SyntheticTrackedFinger
    let midiNote: Int?
    let heightMeters: Float?
    let worldPosition: [Float]?

    func position(keyboardGeometry: PianoKeyboardGeometry) throws -> SIMD3<Float> {
        try syntheticPosition(
            midiNote: midiNote,
            heightMeters: heightMeters,
            worldPosition: worldPosition,
            keyboardGeometry: keyboardGeometry
        )
    }
}

private struct SyntheticPalmSample: Decodable {
    let hand: SyntheticTrackedHand
    let midiNote: Int?
    let heightMeters: Float?
    let worldPosition: [Float]?

    func position(keyboardGeometry: PianoKeyboardGeometry) throws -> SIMD3<Float> {
        try syntheticPosition(
            midiNote: midiNote,
            heightMeters: heightMeters,
            worldPosition: worldPosition,
            keyboardGeometry: keyboardGeometry
        )
    }
}

private enum SyntheticTrackedHand: String, Decodable {
    case left
    case right

    var model: TrackedHandSide {
        switch self {
        case .left: .left
        case .right: .right
        }
    }
}

private enum SyntheticTrackedFinger: String, Decodable {
    case thumb
    case index
    case middle
    case ring
    case little

    var model: TrackedFinger {
        switch self {
        case .thumb: .thumb
        case .index: .index
        case .middle: .middle
        case .ring: .ring
        case .little: .little
        }
    }
}

private func syntheticPosition(
    midiNote: Int?,
    heightMeters: Float?,
    worldPosition: [Float]?,
    keyboardGeometry: PianoKeyboardGeometry
) throws -> SIMD3<Float> {
    if let midiNote {
        guard let key = keyboardGeometry.key(for: midiNote) else {
            throw SyntheticHandContactTraceFixtureError.missingKey(midiNote)
        }
        let localPosition = SIMD3<Float>(
            key.hitCenterLocal.x,
            key.surfaceLocalY + (heightMeters ?? 0),
            key.hitCenterLocal.z
        )
        let world = simd_mul(keyboardGeometry.frame.worldFromKeyboard, SIMD4<Float>(localPosition, 1))
        return SIMD3<Float>(world.x, world.y, world.z)
    }

    guard
        let worldPosition,
        worldPosition.count == 3,
        worldPosition.allSatisfy(\.isFinite)
    else {
        throw SyntheticHandContactTraceFixtureError.invalidWorldPosition
    }
    return SIMD3<Float>(worldPosition[0], worldPosition[1], worldPosition[2])
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
