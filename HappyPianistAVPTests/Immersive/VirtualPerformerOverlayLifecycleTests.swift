@testable import HappyPianistAVP
import simd
import Testing

@MainActor
@Test
func virtualPerformerResetCancelsAndReleasesAllRuntimeResources() throws {
    let geometry = try #require(
        VirtualPianoKeyGeometryService().generateKeyboardGeometry(
            from: KeyboardFrame(worldFromKeyboard: matrix_identity_float4x4)
        )
    )
    let controller = VirtualPerformerOverlayController()

    controller.update(
        isEnabled: true,
        isPerforming: false,
        keyboardGeometry: geometry,
        content: nil
    )
    #expect(controller.hasActiveRuntimeResources)

    controller.reset()
    #expect(controller.hasActiveRuntimeResources == false)

    controller.reset()
    #expect(controller.hasActiveRuntimeResources == false)
}
