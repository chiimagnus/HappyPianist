import Foundation
import simd

struct FingerMotionEstimate: Equatable {
    enum Status: Equatable {
        case initializing
        case valid
        case invalidInterval
        case trackingJump
        case lowConfidence
    }

    let status: Status
    let position: SIMD3<Float>
    let previousPosition: SIMD3<Float>?
    let sampleIntervalSeconds: TimeInterval?
    let normalVelocityMetersPerSecond: Float?
    let normalAccelerationMetersPerSecondSquared: Float?
    let confidence: Float

    var isPositionReliable: Bool {
        status == .initializing || status == .valid
    }

    var hasValidMotion: Bool {
        status == .valid
    }
}

struct FingerMotionEstimator {
    private struct State {
        let position: SIMD3<Float>
        let timestamp: PerformanceMonotonicInstant
        let normalVelocityMetersPerSecond: Float?
    }

    private let minimumSampleIntervalSeconds: TimeInterval
    private let maximumSampleIntervalSeconds: TimeInterval
    private let maximumTrackingJumpMeters: Float
    private let minimumConfidence: Float
    private var stateByFinger: [TrackedFingerID: State] = [:]

    // ponytail: these are ARKit sample-sanity bounds, not piano touch calibration.
    // Add a tracked-device profile only if another hand provider has different timing or jump characteristics.
    init(
        minimumSampleIntervalSeconds: TimeInterval = 1.0 / 240.0,
        maximumSampleIntervalSeconds: TimeInterval = 0.2,
        maximumTrackingJumpMeters: Float = 0.15,
        minimumConfidence: Float = 0.5
    ) {
        self.minimumSampleIntervalSeconds = max(0, minimumSampleIntervalSeconds)
        self.maximumSampleIntervalSeconds = max(self.minimumSampleIntervalSeconds, maximumSampleIntervalSeconds)
        self.maximumTrackingJumpMeters = max(0, maximumTrackingJumpMeters)
        self.minimumConfidence = min(1, max(0, minimumConfidence))
    }

    mutating func estimate(
        fingerID: TrackedFingerID,
        position: SIMD3<Float>,
        at timestamp: PerformanceMonotonicInstant,
        confidence: Float = 1
    ) -> FingerMotionEstimate {
        let clampedConfidence = min(1, max(0, confidence))
        guard clampedConfidence >= minimumConfidence else {
            stateByFinger.removeValue(forKey: fingerID)
            return invalidEstimate(
                status: .lowConfidence,
                position: position,
                confidence: clampedConfidence
            )
        }

        guard let previous = stateByFinger[fingerID] else {
            stateByFinger[fingerID] = State(
                position: position,
                timestamp: timestamp,
                normalVelocityMetersPerSecond: nil
            )
            return FingerMotionEstimate(
                status: .initializing,
                position: position,
                previousPosition: nil,
                sampleIntervalSeconds: nil,
                normalVelocityMetersPerSecond: nil,
                normalAccelerationMetersPerSecondSquared: nil,
                confidence: clampedConfidence
            )
        }

        let intervalNanoseconds = timestamp.nanoseconds - previous.timestamp.nanoseconds
        let interval = TimeInterval(intervalNanoseconds) / 1_000_000_000
        guard interval > 0, interval <= maximumSampleIntervalSeconds else {
            stateByFinger[fingerID] = State(
                position: position,
                timestamp: timestamp,
                normalVelocityMetersPerSecond: nil
            )
            return invalidEstimate(
                status: .invalidInterval,
                position: position,
                previousPosition: previous.position,
                sampleIntervalSeconds: interval,
                confidence: clampedConfidence
            )
        }
        guard interval >= minimumSampleIntervalSeconds else {
            return invalidEstimate(
                status: .invalidInterval,
                position: position,
                previousPosition: previous.position,
                sampleIntervalSeconds: interval,
                confidence: clampedConfidence
            )
        }

        let delta = position - previous.position
        guard simd_length(delta) <= maximumTrackingJumpMeters else {
            stateByFinger[fingerID] = State(
                position: position,
                timestamp: timestamp,
                normalVelocityMetersPerSecond: nil
            )
            return invalidEstimate(
                status: .trackingJump,
                position: position,
                previousPosition: previous.position,
                sampleIntervalSeconds: interval,
                confidence: clampedConfidence
            )
        }

        let normalVelocity = delta.y / Float(interval)
        let normalAcceleration = previous.normalVelocityMetersPerSecond.map {
            (normalVelocity - $0) / Float(interval)
        }
        stateByFinger[fingerID] = State(
            position: position,
            timestamp: timestamp,
            normalVelocityMetersPerSecond: normalVelocity
        )
        return FingerMotionEstimate(
            status: .valid,
            position: position,
            previousPosition: previous.position,
            sampleIntervalSeconds: interval,
            normalVelocityMetersPerSecond: normalVelocity,
            normalAccelerationMetersPerSecondSquared: normalAcceleration,
            confidence: clampedConfidence
        )
    }

    mutating func retainOnly(_ fingerIDs: Set<TrackedFingerID>) {
        stateByFinger = stateByFinger.filter { fingerIDs.contains($0.key) }
    }

    mutating func reset() {
        stateByFinger.removeAll(keepingCapacity: true)
    }

    private func invalidEstimate(
        status: FingerMotionEstimate.Status,
        position: SIMD3<Float>,
        previousPosition: SIMD3<Float>? = nil,
        sampleIntervalSeconds: TimeInterval? = nil,
        confidence: Float
    ) -> FingerMotionEstimate {
        FingerMotionEstimate(
            status: status,
            position: position,
            previousPosition: previousPosition,
            sampleIntervalSeconds: sampleIntervalSeconds,
            normalVelocityMetersPerSecond: nil,
            normalAccelerationMetersPerSecondSquared: nil,
            confidence: confidence
        )
    }
}
