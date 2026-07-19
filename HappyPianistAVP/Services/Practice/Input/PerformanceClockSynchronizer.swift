import Foundation

struct PerformanceClockSynchronizer {
    private struct Sample {
        let sourceSeconds: TimeInterval
        let correctedHostSeconds: TimeInterval
    }

    private struct SourceState {
        var first: Sample
        var last: Sample
        var sampleCount: Int
    }

    private let maximumLatencySeconds: TimeInterval
    private let maximumDriftRatio: Double
    private var states: [String: SourceState] = [:]

    init(maximumLatencySeconds: TimeInterval = 2, maximumDriftRatio: Double = 0.02) {
        self.maximumLatencySeconds = max(0, maximumLatencySeconds)
        self.maximumDriftRatio = max(0, maximumDriftRatio)
    }

    mutating func reading(
        source: PerformanceSourceTimestamp?,
        receivedAt host: PerformanceMonotonicInstant,
        estimatedLatencySeconds: TimeInterval? = nil
    ) -> PerformanceClockReading {
        let latency = clampedLatency(estimatedLatencySeconds)
        let correctedArrival = host.advanced(by: -latency)
        guard let source,
              source.clockID.isEmpty == false,
              source.seconds.isFinite,
              source.seconds >= 0
        else {
            return PerformanceClockReading(
                host: host,
                source: source,
                correctedHost: correctedArrival,
                mapping: nil,
                provenance: latency > 0 ? .latencyEstimate : .hostOnly
            )
        }

        let sample = Sample(
            sourceSeconds: source.seconds,
            correctedHostSeconds: correctedArrival.seconds
        )
        let mapping = updateMapping(clockID: source.clockID, with: sample, latency: latency)
        let corrected = PerformanceMonotonicInstant(
            seconds: source.seconds * mapping.rate + mapping.offsetSeconds
        )
        return PerformanceClockReading(
            host: host,
            source: source,
            correctedHost: corrected,
            mapping: mapping,
            provenance: mapping.provenance
        )
    }

    mutating func reset(sourceClockID: String? = nil) {
        if let sourceClockID {
            states[sourceClockID] = nil
        } else {
            states.removeAll(keepingCapacity: true)
        }
    }

    private func clampedLatency(_ latency: TimeInterval?) -> TimeInterval {
        guard let latency, latency.isFinite else { return 0 }
        return max(0, min(maximumLatencySeconds, latency))
    }

    private mutating func updateMapping(
        clockID: String,
        with sample: Sample,
        latency: TimeInterval
    ) -> PerformanceClockMapping {
        guard var state = states[clockID] else {
            let state = SourceState(first: sample, last: sample, sampleCount: 1)
            states[clockID] = state
            return mapping(clockID: clockID, state: state, rate: 1, latency: latency)
        }

        let sourceDelta = sample.sourceSeconds - state.first.sourceSeconds
        let hostDelta = sample.correctedHostSeconds - state.first.correctedHostSeconds
        guard sourceDelta > 0, hostDelta >= 0 else {
            if sourceDelta < 0 || hostDelta < 0 {
                state = SourceState(first: sample, last: sample, sampleCount: 1)
                states[clockID] = state
            }
            return mapping(clockID: clockID, state: state, rate: 1, latency: latency)
        }

        let rate = hostDelta / sourceDelta
        guard rate.isFinite, abs(rate - 1) <= maximumDriftRatio else {
            state = SourceState(first: sample, last: sample, sampleCount: 1)
            states[clockID] = state
            return mapping(clockID: clockID, state: state, rate: 1, latency: latency)
        }

        state.last = sample
        state.sampleCount += 1
        states[clockID] = state
        return mapping(clockID: clockID, state: state, rate: rate, latency: latency)
    }

    private func mapping(
        clockID: String,
        state: SourceState,
        rate: Double,
        latency: TimeInterval
    ) -> PerformanceClockMapping {
        PerformanceClockMapping(
            sourceClockID: clockID,
            offsetSeconds: state.first.correctedHostSeconds - state.first.sourceSeconds * rate,
            rate: rate,
            sampleCount: state.sampleCount,
            estimatedLatencySeconds: latency,
            provenance: state.sampleCount > 1 ? .offsetAndDriftSamples : .offsetSample
        )
    }
}
