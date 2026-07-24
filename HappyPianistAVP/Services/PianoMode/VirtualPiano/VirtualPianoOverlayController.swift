import RealityKit
import simd
import SwiftUI

@MainActor
final class VirtualPianoOverlayController {
    private let keyEntityFactory: PianoKeyEntityFactory
    private var rootEntity = Entity()
    private var hasAttachedRoot = false
    private var keyboardRootEntity: Entity?

    init(keyEntityFactory: PianoKeyEntityFactory = PianoKeyEntityFactory()) {
        self.keyEntityFactory = keyEntityFactory
    }

    func update(
        isEnabled: Bool,
        keyboardGeometry: PianoKeyboardGeometry?,
        reduceMotion: Bool,
        content: RealityViewContent?
    ) {
        if hasAttachedRoot == false, let content {
            content.add(rootEntity)
            hasAttachedRoot = true
        }

        guard isEnabled, let keyboardGeometry else {
            clearKeyboard()
            return
        }

        showKeyboard(geometry: keyboardGeometry, reduceMotion: reduceMotion)
    }

    func reset() {
        clearKeyboard()
        rootEntity.removeFromParent()
        hasAttachedRoot = false
    }

    private func showKeyboard(geometry: PianoKeyboardGeometry, reduceMotion: Bool) {
        guard keyboardRootEntity == nil else { return }

        let totalLength = VirtualPianoKeyGeometryService.totalKeyboardLengthMeters
        let keyDepth = VirtualPianoKeyGeometryService.whiteKeyDepthMeters
        let keyboardCenterLocal = SIMD3<Float>(totalLength / 2, 0, -keyDepth / 2)

        let worldFromKeyboard = geometry.frame.worldFromKeyboard
        let xAxisWorld = SIMD3<Float>(
            worldFromKeyboard.columns.0.x,
            worldFromKeyboard.columns.0.y,
            worldFromKeyboard.columns.0.z
        )
        let yAxisWorld = SIMD3<Float>(
            worldFromKeyboard.columns.1.x,
            worldFromKeyboard.columns.1.y,
            worldFromKeyboard.columns.1.z
        )
        let zAxisWorld = SIMD3<Float>(
            worldFromKeyboard.columns.2.x,
            worldFromKeyboard.columns.2.y,
            worldFromKeyboard.columns.2.z
        )
        let originWorld = SIMD3<Float>(
            worldFromKeyboard.columns.3.x,
            worldFromKeyboard.columns.3.y,
            worldFromKeyboard.columns.3.z
        )
        let centerWorld = originWorld
            + xAxisWorld * keyboardCenterLocal.x
            + yAxisWorld * keyboardCenterLocal.y
            + zAxisWorld * keyboardCenterLocal.z

        var kbWorldFromCenter = worldFromKeyboard
        kbWorldFromCenter.columns.3 = SIMD4<Float>(centerWorld, 1)

        let kbRoot = Entity()
        kbRoot.transform = Transform(matrix: kbWorldFromCenter)

        let kbContent = Entity()
        kbContent.position = -keyboardCenterLocal

        for key in geometry.keys {
            let keyEntity = keyEntityFactory.makeEntity(for: key)
            kbContent.addChild(keyEntity)
        }

        kbRoot.addChild(kbContent)

        rootEntity.addChild(kbRoot)
        keyboardRootEntity = kbRoot

        animateKeyboardIn(kbRoot, reduceMotion: reduceMotion)
    }

    private func clearKeyboard() {
        keyboardRootEntity?.removeFromParent()
        keyboardRootEntity = nil
    }

    private func animateKeyboardIn(_ keyboardRoot: Entity, reduceMotion: Bool) {
        if reduceMotion {
            keyboardRoot.transform.scale = .one
            return
        }

        #if targetEnvironment(simulator)
            // RealityKit's `move(to:)` animation does not reliably interpolate scale in the simulator.
            // If we keep a near-zero X scale here, all 88 keys collapse into a single white+black stack.
            keyboardRoot.transform.scale = .one
        #else
            let endTransform = keyboardRoot.transform
            var startTransform = endTransform
            startTransform.scale = SIMD3<Float>(0.001, 1, 1)
            keyboardRoot.transform = startTransform
            _ = keyboardRoot.move(
                to: endTransform,
                relativeTo: keyboardRoot.parent,
                duration: 0.35,
                timingFunction: .easeOut
            )
        #endif
    }
}
