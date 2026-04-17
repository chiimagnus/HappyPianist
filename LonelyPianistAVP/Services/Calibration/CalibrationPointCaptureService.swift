import Foundation
import Observation
import simd

enum CalibrationAnchorPoint {
    case a0
    case c8
}

enum CalibrationCaptureMode: Equatable {
    case raycast
    case manualFallback
}

@MainActor
@Observable
final class CalibrationPointCaptureService {
    var mode: CalibrationCaptureMode = .raycast
    var reticlePoint: SIMD3<Float> = SIMD3<Float>(0, 0.8, -1.0)
    var a0Point: SIMD3<Float>?
    var c8Point: SIMD3<Float>?

    func updateReticleEstimate(_ point: SIMD3<Float>?) {
        guard let point else {
            mode = .manualFallback
            return
        }
        mode = .raycast
        reticlePoint = point
    }

    func capture(_ anchor: CalibrationAnchorPoint) {
        switch anchor {
        case .a0:
            a0Point = reticlePoint
        case .c8:
            c8Point = reticlePoint
        }
    }

    func adjust(anchor: CalibrationAnchorPoint, delta: SIMD3<Float>) {
        mode = .manualFallback
        switch anchor {
        case .a0:
            let current = a0Point ?? SIMD3<Float>(-0.7, reticlePoint.y, reticlePoint.z)
            a0Point = current + delta
        case .c8:
            let current = c8Point ?? SIMD3<Float>(0.7, reticlePoint.y, reticlePoint.z)
            c8Point = current + delta
        }
    }

    func buildCalibration() -> PianoCalibration? {
        guard let a0Point, let c8Point else {
            return nil
        }
        guard simd_length(c8Point - a0Point) > 0.05 else {
            return nil
        }
        return PianoCalibration(a0: a0Point, c8: c8Point, planeHeight: (a0Point.y + c8Point.y) / 2)
    }
}
