import Foundation
import simd

@MainActor
final class KeyContactDetectionService {
    let calibration: PianoTouchCalibration
    private let velocityResolver: PianoTouchVelocityResolver
    private var tracker = PianoKeyContactTracker()

    init(
        calibration: PianoTouchCalibration = PianoModeTouchCalibrationService.conservativeDefault(
            for: .virtualPiano
        )
    ) {
        self.calibration = calibration
        velocityResolver = PianoTouchVelocityResolver(calibration: calibration)
    }

    func reset() {
        tracker.reset()
    }

    func detect(
        fingerTips: FingerTipsSnapshot,
        keyboardGeometry: PianoKeyboardGeometry,
        at timestamp: PerformanceMonotonicInstant
    ) -> [PianoKeyContactObservation] {
        tracker.detect(
            fingerTips: fingerTips,
            keyboardGeometry: keyboardGeometry,
            at: timestamp,
            pressThresholdMeters: calibration.planeOffsetMeters,
            releaseThresholdMeters: calibration.releaseThresholdMeters,
            retriggerDebounceSeconds: calibration.retriggerDebounceSeconds,
            calibrationID: calibration.id,
            velocityResolver: velocityResolver
        )
    }
}
