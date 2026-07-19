import Foundation
import simd

struct HandGateState: Equatable {
    let isNearKeyboard: Bool
    let hasDownwardMotion: Bool
    let exactPressedNotes: Set<Int>
    let confidenceBoost: Double
}

final class HandPianoActivityGate {
    private struct KeyboardBounds {
        let x: ClosedRange<Float>
        let y: ClosedRange<Float>
        let z: ClosedRange<Float>
    }

    private let nearDistance: Float
    private let downwardVelocityThresholdMetersPerSecond: Float
    private var motionEstimator = FingerMotionEstimator()
    private var cachedGeometryID: UUID?
    private var cachedBounds: KeyboardBounds?

    init(
        nearDistance: Float = 0.06,
        downwardVelocityThresholdMetersPerSecond: Float = 0.08
    ) {
        self.nearDistance = nearDistance
        self.downwardVelocityThresholdMetersPerSecond = downwardVelocityThresholdMetersPerSecond
    }

    func evaluate(
        fingerTips: FingerTipsSnapshot,
        keyboardGeometry: PianoKeyboardGeometry?,
        exactPressedNotes: Set<Int>,
        at timestamp: PerformanceMonotonicInstant
    ) -> HandGateState {
        guard let keyboardGeometry else {
            motionEstimator.reset()
            return HandGateState(
                isNearKeyboard: false,
                hasDownwardMotion: false,
                exactPressedNotes: exactPressedNotes,
                confidenceBoost: exactPressedNotes.isEmpty ? 0 : 0.10
            )
        }

        let keyboardFromWorld = keyboardGeometry.frame.keyboardFromWorld
        if let cachedGeometryID, cachedGeometryID != keyboardGeometry.cacheID {
            motionEstimator.reset()
        }
        let bounds = bounds(for: keyboardGeometry)
        var isNearKeyboard = false
        var hasDownwardMotion = false
        var observedFingerIDs: Set<TrackedFingerID> = []

        fingerTips.forEachFinger { fingerID, worldPoint in
            observedFingerIDs.insert(fingerID)
            let localPoint = Self.transformPoint(keyboardFromWorld, worldPoint)
            let motion = motionEstimator.estimate(
                fingerID: fingerID,
                position: localPoint,
                at: timestamp
            )
            guard motion.isPositionReliable else { return }

            if localPoint.y <= bounds.y.upperBound + nearDistance,
               localPoint.y >= bounds.y.lowerBound - nearDistance,
               bounds.x.contains(localPoint.x),
               bounds.z.contains(localPoint.z)
            {
                isNearKeyboard = true
            }

            if motion.hasValidMotion,
               let normalVelocity = motion.normalVelocityMetersPerSecond,
               normalVelocity < -downwardVelocityThresholdMetersPerSecond
            {
                hasDownwardMotion = true
            }
        }
        motionEstimator.retainOnly(observedFingerIDs)

        let confidenceBoost: Double = if exactPressedNotes.isEmpty == false {
            0.10
        } else if isNearKeyboard, hasDownwardMotion {
            0.12
        } else if isNearKeyboard {
            0.06
        } else {
            0
        }

        return HandGateState(
            isNearKeyboard: isNearKeyboard,
            hasDownwardMotion: hasDownwardMotion,
            exactPressedNotes: exactPressedNotes,
            confidenceBoost: confidenceBoost
        )
    }

    func reset() {
        motionEstimator.reset()
    }

    private static func transformPoint(
        _ matrix: simd_float4x4,
        _ point: SIMD3<Float>
    ) -> SIMD3<Float> {
        let value = simd_mul(matrix, SIMD4<Float>(point, 1))
        return SIMD3<Float>(value.x, value.y, value.z)
    }

    private func bounds(for geometry: PianoKeyboardGeometry) -> KeyboardBounds {
        if cachedGeometryID == geometry.cacheID, let cachedBounds {
            return cachedBounds
        }

        guard let first = geometry.keys.first else {
            let fallback = KeyboardBounds(x: -1 ... 1, y: -0.02 ... 0.03, z: -1 ... 1)
            cachedGeometryID = geometry.cacheID
            cachedBounds = fallback
            return fallback
        }

        var minX = first.localCenter.x - first.localSize.x / 2
        var maxX = first.localCenter.x + first.localSize.x / 2
        var minY = first.surfaceLocalY - 0.02
        var maxY = first.surfaceLocalY + 0.03
        var minZ = first.localCenter.z - first.localSize.z / 2
        var maxZ = first.localCenter.z + first.localSize.z / 2

        for key in geometry.keys.dropFirst() {
            minX = min(minX, key.localCenter.x - key.localSize.x / 2)
            maxX = max(maxX, key.localCenter.x + key.localSize.x / 2)
            minY = min(minY, key.surfaceLocalY - 0.02)
            maxY = max(maxY, key.surfaceLocalY + 0.03)
            minZ = min(minZ, key.localCenter.z - key.localSize.z / 2)
            maxZ = max(maxZ, key.localCenter.z + key.localSize.z / 2)
        }

        let next = KeyboardBounds(x: minX ... maxX, y: minY ... maxY, z: minZ ... maxZ)
        cachedGeometryID = geometry.cacheID
        cachedBounds = next
        return next
    }
}
