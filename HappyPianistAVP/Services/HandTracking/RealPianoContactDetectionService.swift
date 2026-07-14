import Foundation
import simd

@MainActor
final class RealPianoContactDetectionService {
    static let pressThresholdMeters: Float = 0.004
    static let releaseThresholdMeters: Float = 0.016

    private var tracker = PianoKeyContactTracker()

    func reset() {
        tracker.reset()
    }

    func detect(
        fingerTips: FingerTipsSnapshot,
        keyboardGeometry: PianoKeyboardGeometry
    ) -> KeyContactResult {
        tracker.detect(
            fingerTips: fingerTips,
            keyboardGeometry: keyboardGeometry,
            pressThresholdMeters: Self.pressThresholdMeters,
            releaseThresholdMeters: Self.releaseThresholdMeters
        )
    }
}
