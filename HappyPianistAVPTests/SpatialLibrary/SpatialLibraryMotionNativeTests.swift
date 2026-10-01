import Foundation
@testable import HappyPianistAVP
import RealityKit
import SwiftUI
import Testing
import UIKit

extension NativeBookWindowTests {
    @Test
    @MainActor
    func spatialFolioMotionInterpolatesInterruptsAndStopsInNativeRealityView() async throws {
        let windowScene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = try #require(windowScene.windows.first { $0.isKeyWindow })
        let original = window.rootViewController
        let controller = SpatialLibrarySceneController()
        let root = try #require(controller.interactionEntity.parent)
        let folio = ModelEntity(mesh: .generateBox(size: 0.02), materials: [SimpleMaterial(color: .white, isMetallic: false)])
        let identity = UUID()
        let mount = SpatialFolioNativeMount()
        root.addChild(folio)
        controller.moveFolio(folio, id: identity, to: Transform(), immediately: true)
        defer {
            controller.reset()
            folio.removeFromParent()
            window.rootViewController = original
        }
        window.rootViewController = UIHostingController(rootView: RealityView { content in
            root.isEnabled = true
            content.add(root)
            mount.isMounted = true
        })
        await TestAsyncWait.until("folio RealityView mounted") { mount.isMounted }
        try await Task.sleep(for: .milliseconds(150))

        let first = Transform(translation: SIMD3<Float>(0.25, 0, 0))
        controller.moveFolio(folio, id: identity, to: first, immediately: false)
        await TestAsyncWait.until("folio interpolates rather than snapping", timeout: .milliseconds(250), pollInterval: .milliseconds(5)) {
            folio.position.x > 0.005 && folio.position.x < 0.245
        }
        let interrupted = folio.position
        let replacement = Transform(translation: SIMD3<Float>(-0.15, 0, 0))
        controller.moveFolio(folio, id: identity, to: replacement, immediately: false)
        #expect(simd_distance(folio.position, interrupted) < 0.001)
        await TestAsyncWait.until("latest folio target wins") { simd_distance(folio.position, replacement.translation) < 0.001 }

        controller.moveFolio(folio, id: identity, to: first, immediately: false)
        let drag = Transform(translation: SIMD3<Float>(0.12, 0, 0))
        controller.moveFolio(folio, id: identity, to: drag, immediately: true)
        try await Task.sleep(for: .milliseconds(450))
        #expect(simd_distance(folio.position, drag.translation) < 0.001)

        controller.moveFolio(folio, id: identity, to: replacement, immediately: false)
        await TestAsyncWait.until("folio moves before teardown", timeout: .milliseconds(250), pollInterval: .milliseconds(5)) {
            folio.position.x < 0.115 && folio.position.x > -0.145
        }
        controller.reset()
        let stopped = folio.position
        root.isEnabled = true
        try await Task.sleep(for: .milliseconds(450))
        #expect(simd_distance(folio.position, stopped) < 0.001)
    }
}

@MainActor
private final class SpatialFolioNativeMount {
    var isMounted = false
}
