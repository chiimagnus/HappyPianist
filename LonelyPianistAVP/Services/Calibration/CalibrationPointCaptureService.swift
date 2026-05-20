import Foundation
import Observation
import simd

enum CalibrationAnchorPoint {
    case a0
    case c8
}

@MainActor
@Observable
final class CalibrationPointCaptureService {
    var reticlePoint: SIMD3<Float> = .init(0, 0.8, -1.0)
    var a0AnchorID: UUID?
    var c8AnchorID: UUID?

    var isReticleReadyToConfirm: Bool = false

    private var stableStartUptime: TimeInterval?
    private var lastReticlePointForStability: SIMD3<Float>?

    func reset() {
        reticlePoint = SIMD3<Float>(0, 0.8, -1.0)
        a0AnchorID = nil
        c8AnchorID = nil
        isReticleReadyToConfirm = false
        stableStartUptime = nil
        lastReticlePointForStability = nil
    }

    func updateReticleFromHandTracking(_ point: SIMD3<Float>?, nowUptime: TimeInterval) {
        guard let point else {
            isReticleReadyToConfirm = false
            stableStartUptime = nil
            lastReticlePointForStability = nil
            return
        }

        reticlePoint = point

        let deltaThresholdMeters: Float = 0.005
        let stableDurationSeconds: TimeInterval = 0.5

        if let last = lastReticlePointForStability {
            let delta = simd_length(point - last)
            if delta < deltaThresholdMeters {
                if stableStartUptime == nil {
                    stableStartUptime = nowUptime
                }
            } else {
                stableStartUptime = nil
            }
        } else {
            stableStartUptime = nil
        }

        lastReticlePointForStability = point

        if let stableStartUptime {
            let stableFor = max(0, nowUptime - stableStartUptime)
            let progress = min(1.0, stableFor / stableDurationSeconds)
            isReticleReadyToConfirm = progress >= 1.0
        } else {
            isReticleReadyToConfirm = false
        }
    }

    func anchorID(for anchor: CalibrationAnchorPoint) -> UUID? {
        switch anchor {
            case .a0:
                a0AnchorID
            case .c8:
                c8AnchorID
        }
    }

    func setAnchorID(_ anchorID: UUID, for anchor: CalibrationAnchorPoint) {
        switch anchor {
            case .a0:
                a0AnchorID = anchorID
            case .c8:
                c8AnchorID = anchorID
        }
    }
}
