import Foundation
import MIDI

public struct PerformanceMonotonicInstant: Codable, Comparable, Hashable, Sendable {
    public let nanoseconds: Int64

    public init(nanoseconds: Int64) {
        self.nanoseconds = max(0, nanoseconds)
    }

    public init(milliseconds: Int64) {
        let (value, overflow) = max(0, milliseconds).multipliedReportingOverflow(by: 1_000_000)
        self.nanoseconds = overflow ? .max : value
    }

    public init(seconds: TimeInterval) {
        guard seconds.isFinite, seconds > 0 else {
            nanoseconds = 0
            return
        }
        let value = seconds * 1_000_000_000
        nanoseconds = value >= Double(Int64.max) ? .max : Int64(value.rounded())
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.nanoseconds < rhs.nanoseconds
    }

    public var seconds: TimeInterval {
        TimeInterval(nanoseconds) / 1_000_000_000
    }

    public var milliseconds: Int64 {
        nanoseconds / 1_000_000
    }

    public func advanced(by interval: TimeInterval) -> Self {
        Self(seconds: seconds + interval)
    }
}

public enum PerformanceClockCorrectionProvenance: String, Codable, Sendable {
    case hostOnly
    case latencyEstimate
    case offsetSample
    case offsetAndDriftSamples
}

public struct PerformanceClockMapping: Codable, Equatable, Sendable {
    public let sourceClockID: String
    public let offsetSeconds: TimeInterval
    public let rate: Double
    public let sampleCount: Int
    public let estimatedLatencySeconds: TimeInterval
    public let provenance: PerformanceClockCorrectionProvenance

    public init(
        sourceClockID: String,
        offsetSeconds: TimeInterval,
        rate: Double,
        sampleCount: Int,
        estimatedLatencySeconds: TimeInterval,
        provenance: PerformanceClockCorrectionProvenance
    ) {
        self.sourceClockID = sourceClockID
        self.offsetSeconds = offsetSeconds
        self.rate = rate
        self.sampleCount = sampleCount
        self.estimatedLatencySeconds = estimatedLatencySeconds
        self.provenance = provenance
    }
}

public struct PerformanceClockReading: Codable, Equatable, Sendable {
    public let host: PerformanceMonotonicInstant
    public let source: PerformanceSourceTimestamp?
    public let correctedHost: PerformanceMonotonicInstant
    public let mapping: PerformanceClockMapping?
    public let provenance: PerformanceClockCorrectionProvenance

    public init(
        host: PerformanceMonotonicInstant,
        source: PerformanceSourceTimestamp?,
        correctedHost: PerformanceMonotonicInstant,
        mapping: PerformanceClockMapping?,
        provenance: PerformanceClockCorrectionProvenance
    ) {
        self.host = host
        self.source = source
        self.correctedHost = correctedHost
        self.mapping = mapping
        self.provenance = provenance
    }
}

public struct PerformanceClock: Sendable {
    public let now: @Sendable () -> PerformanceMonotonicInstant

    public init(now: @escaping @Sendable () -> PerformanceMonotonicInstant) {
        self.now = now
    }

    public static func live() -> Self {
        Self {
            PerformanceMonotonicInstant(seconds: ProcessInfo.processInfo.systemUptime)
        }
    }
}
