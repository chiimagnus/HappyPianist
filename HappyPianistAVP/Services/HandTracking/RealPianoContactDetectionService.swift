import Foundation
import simd

@MainActor
final class RealPianoContactDetectionService {
    static let pressThresholdMeters: Float = 0.004
    static let releaseThresholdMeters: Float = 0.016
    static let retriggerDebounceSeconds: TimeInterval = 0.03

    private var tracker = PianoKeyContactTracker()

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
            pressThresholdMeters: Self.pressThresholdMeters,
            releaseThresholdMeters: Self.releaseThresholdMeters,
            retriggerDebounceSeconds: Self.retriggerDebounceSeconds
        )
    }
}
