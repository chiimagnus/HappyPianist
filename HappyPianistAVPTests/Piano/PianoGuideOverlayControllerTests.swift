@testable import HappyPianistAVP
import Practice
import RealityKit
import simd
import Testing

@MainActor
struct PianoGuideOverlayControllerTests {
    @Test func disabledHighlightsStillAlignTheRestorationParent() throws {
        let keyboardRoot = Entity()
        let controller = PianoGuideOverlayController(keyboardRootEntity: keyboardRoot)
        let frame = try #require(KeyboardFrame(
            a0World: SIMD3<Float>(0, 0.5, 0),
            c8World: SIMD3<Float>(1, 0.5, 0),
            planeHeight: 0.5
        ))

        controller.updateHighlights(
            isEnabled: false,
            highlightGuide: nil,
            keyboardGeometry: PianoKeyboardGeometry(frame: frame, keys: []),
            differentiateWithoutColor: false,
            content: nil
        )

        #expect(abs(keyboardRoot.position.y - 0.5) < 0.0001)
    }
}
