import Foundation
import Observation
import simd

@MainActor
@Observable
final class GazePlaneDiskConfirmationViewModel {
    private static let diskRadiusMeters: Float = 0.23
    private static let planeDistanceThresholdMeters: Float = 0.05
    private static let stableThresholdMeters: Float = 0.03
    private static let stableDurationSeconds: TimeInterval = 3.0

    private(set) var isDiskVisible: Bool = false
    private(set) var diskWorldTransform: simd_float4x4?
    private(set) var statusText: String?
    private(set) var confirmationProgress: Double?
    private(set) var isConfirmed: Bool = false

    private var stableStartUptime: TimeInterval?
    private var stableReferenceHandPointOnPlaneWorld: SIMD3<Float>?

    func reset() {
        isDiskVisible = false
        diskWorldTransform = nil
        statusText = nil
        confirmationProgress = nil
        isConfirmed = false
        stableStartUptime = nil
        stableReferenceHandPointOnPlaneWorld = nil
    }

    func update(
        planeHit: PlaneHit?,
        leftPalmWorld: SIMD3<Float>?,
        rightPalmWorld: SIMD3<Float>?,
        nowUptime: TimeInterval
    ) {
        guard let planeHit else {
            reset()
            return
        }

        isDiskVisible = true
        diskWorldTransform = computeDiskWorldTransform(planeHit: planeHit)

        if isConfirmed {
            confirmationProgress = 1
            statusText = "已确认"
            return
        }

        guard let leftPalmWorld, let rightPalmWorld else {
            stableStartUptime = nil
            stableReferenceHandPointOnPlaneWorld = nil
            confirmationProgress = nil
            statusText = "放好双手"
            return
        }

        let centerWorld = (leftPalmWorld + rightPalmWorld) / 2
        let planeNormalWorld = simd_normalize(planeHit.planeNormalWorld)
        let centerOnPlaneWorld = projectPointOntoPlane(
            centerWorld,
            planeOriginWorld: planeHit.hitPointWorld,
            planeNormalWorld: planeNormalWorld
        )

        guard areHandsPlaced(
            planeHit: planeHit,
            planeNormalWorld: planeNormalWorld,
            leftPalmWorld: leftPalmWorld,
            rightPalmWorld: rightPalmWorld
        ) else {
            stableStartUptime = nil
            stableReferenceHandPointOnPlaneWorld = nil
            confirmationProgress = nil
            statusText = "放好双手"
            return
        }

        if stableStartUptime == nil {
            stableStartUptime = nowUptime
            stableReferenceHandPointOnPlaneWorld = centerOnPlaneWorld
        } else if let stableReferenceHandPointOnPlaneWorld {
            let delta = centerOnPlaneWorld - stableReferenceHandPointOnPlaneWorld
            let deltaOnPlane = delta - planeNormalWorld * simd_dot(delta, planeNormalWorld)
            if simd_length(deltaOnPlane) >= Self.stableThresholdMeters {
                stableStartUptime = nowUptime
                self.stableReferenceHandPointOnPlaneWorld = centerOnPlaneWorld
            }
        }

        let stableFor = max(0, nowUptime - (stableStartUptime ?? nowUptime))
        let progress = min(1.0, stableFor / Self.stableDurationSeconds)
        confirmationProgress = progress
        statusText = "保持不动 \(Int(progress * 100))%"

        if progress >= 1.0 {
            isConfirmed = true
            statusText = "已确认"
        }
    }

    private func areHandsPlaced(
        planeHit: PlaneHit,
        planeNormalWorld: SIMD3<Float>,
        leftPalmWorld: SIMD3<Float>,
        rightPalmWorld: SIMD3<Float>
    ) -> Bool {
        func isHandPlaced(_ handWorld: SIMD3<Float>) -> Bool {
            let toPlane = handWorld - planeHit.hitPointWorld
            let distance = abs(simd_dot(toPlane, planeNormalWorld))
            if distance > Self.planeDistanceThresholdMeters { return false }

            let handOnPlane = handWorld - planeNormalWorld * simd_dot(toPlane, planeNormalWorld)
            let deltaOnPlane = handOnPlane - planeHit.hitPointWorld
            let planarDistance = simd_length(deltaOnPlane)
            return planarDistance <= Self.diskRadiusMeters
        }

        return isHandPlaced(leftPalmWorld) && isHandPlaced(rightPalmWorld)
    }

    private func computeDiskWorldTransform(planeHit: PlaneHit) -> simd_float4x4 {
        let yAxisWorld = simd_normalize(planeHit.planeNormalWorld)

        let refA = SIMD3<Float>(0, 0, 1)
        let refB = SIMD3<Float>(1, 0, 0)
        let ref = abs(simd_dot(yAxisWorld, refA)) < 0.98 ? refA : refB

        let xAxisWorld = simd_normalize(simd_cross(ref, yAxisWorld))
        let zAxisWorld = simd_normalize(simd_cross(yAxisWorld, xAxisWorld))

        let originWorld = planeHit.hitPointWorld

        return simd_float4x4(columns: (
            SIMD4<Float>(xAxisWorld, 0),
            SIMD4<Float>(yAxisWorld, 0),
            SIMD4<Float>(zAxisWorld, 0),
            SIMD4<Float>(originWorld, 1)
        ))
    }

    private func projectPointOntoPlane(
        _ pointWorld: SIMD3<Float>,
        planeOriginWorld: SIMD3<Float>,
        planeNormalWorld: SIMD3<Float>
    ) -> SIMD3<Float> {
        let v = pointWorld - planeOriginWorld
        let distanceAlongNormal = simd_dot(v, planeNormalWorld)
        return pointWorld - planeNormalWorld * distanceAlongNormal
    }
}

