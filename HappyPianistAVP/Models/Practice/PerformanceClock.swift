import Foundation

struct PerformanceMonotonicInstant: Codable, Comparable, Hashable, Sendable {
    let nanoseconds: Int64

    init(nanoseconds: Int64) {
        self.nanoseconds = max(0, nanoseconds)
    }

    init(milliseconds: Int64) {
        let (value, overflow) = max(0, milliseconds).multipliedReportingOverflow(by: 1_000_000)
        self.nanoseconds = overflow ? .max : value
    }

    init(seconds: TimeInterval) {
        guard seconds.isFinite, seconds > 0 else {
            nanoseconds = 0
            return
        }
        let value = seconds * 1_000_000_000
        nanoseconds = value >= Double(Int64.max) ? .max : Int64(value.rounded())
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.nanoseconds < rhs.nanoseconds
    }

    var seconds: TimeInterval {
        TimeInterval(nanoseconds) / 1_000_000_000
    }

    var milliseconds: Int64 {
        nanoseconds / 1_000_000
    }

    func advanced(by interval: TimeInterval) -> Self {
        Self(seconds: seconds + interval)
    }
}

struct PerformanceSourceTimestamp: Codable, Equatable, Sendable {
    let clockID: String
    let seconds: TimeInterval
}

enum PerformanceClockCorrectionProvenance: String, Codable, Sendable {
    case hostOnly
    case latencyEstimate
    case offsetSample
    case offsetAndDriftSamples
}

struct PerformanceClockMapping: Codable, Equatable, Sendable {
    let sourceClockID: String
    let offsetSeconds: TimeInterval
    let rate: Double
    let sampleCount: Int
    let estimatedLatencySeconds: TimeInterval
    let provenance: PerformanceClockCorrectionProvenance
}

struct PerformanceClockReading: Codable, Equatable, Sendable {
    let host: PerformanceMonotonicInstant
    let source: PerformanceSourceTimestamp?
    let correctedHost: PerformanceMonotonicInstant
    let mapping: PerformanceClockMapping?
    let provenance: PerformanceClockCorrectionProvenance
}

struct PerformanceClock: Sendable {
    let now: @Sendable () -> PerformanceMonotonicInstant

    static func live() -> Self {
        return Self {
            PerformanceMonotonicInstant(seconds: ProcessInfo.processInfo.systemUptime)
        }
    }
}
