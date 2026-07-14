import Foundation
import simd

struct KeyContactResult: Equatable {
    let down: Set<Int>
    let started: Set<Int>
    let ended: Set<Int>
}

@MainActor
final class KeyContactDetectionService {
    static let pressThresholdMeters: Float = 0.002
    static let releaseThresholdMeters: Float = 0.008

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
