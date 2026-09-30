import Library
import Foundation
import MusicXML
import Notation
import Observation
import Practice
import SwiftUI
import Testing
import UIKit
@testable import HappyPianistAVP

@Test
@MainActor
func productionLibraryOpensRealSpreadAndReturnsToSameFolioInExistingWindow() async throws {
    let graph = LiveAppGraph.make()
    let library = graph.songLibraryViewModel
    let lifecycle = PreviewNativeLifecycle()
    let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let window = try #require(scene.windows.first { $0.isKeyWindow })
    let original = window.rootViewController
    let size = window.bounds.size
    let minimum = scene.sizeRestrictions?.minimumSize
    let maximum = scene.sizeRestrictions?.maximumSize
    defer {
        library.scorePreview.close()
        library.stopListening()
        window.rootViewController = original
        scene.requestGeometryUpdate(.Vision(size: size, minimumSize: minimum, maximumSize: maximum))
    }
    scene.requestGeometryUpdate(.Vision(size: CGSize(width: 1240, height: 1000), minimumSize: CGSize(width: 1240, height: 1000), maximumSize: CGSize(width: 1240, height: 1000)))
    let controller = UIHostingController(rootView: PreviewNativeRoot(graph: graph, lifecycle: lifecycle))
    controller.traitOverrides.accessibilityContrast = .high
    window.rootViewController = controller
    await TestAsyncWait.until("production library loaded") { !library.entries.isEmpty && window.bounds.width >= 1239 }
    let entry = try #require(library.entries.first { $0.id == UUID(uuidString: "3d7487e7-0cc0-578f-9581-9dc847f85f62") })
    library.selectEntry(entry.id)
    library.confirmFolio(entry.id)
    await TestAsyncWait.until("production real score", timeout: .seconds(30)) { if case .ready = library.scorePreview.state { return true }; return false }
    let plan = try #require(library.scorePreview.pageOwner.plan)
    #expect(plan.input.identity.songID == entry.id)
    #expect(plan.spreadCount > 1)
    #expect(library.scorePreview.prepared?.scoreContext.orderSelection.applied == .written)
    #expect(library.currentListeningEntryID == nil)
    controller.view.layoutIfNeeded()
    try await Task.sleep(for: .seconds(1))
    #expect(library.scorePreview.targetSpreadIndex == 0)
    library.scorePreview.turn(forward: true)
    #expect(library.scorePreview.targetSpreadIndex == 1)
    try await Task.sleep(for: .seconds(1))
    library.scorePreview.turn(forward: false)
    #expect(library.scorePreview.targetSpreadIndex == 0)
    try await Task.sleep(for: .seconds(1))
    lifecycle.phase = .inactive
    await TestAsyncWait.until("inactive scene closes actual preview") { !library.scorePreview.isOpen }
    #expect(library.scorePreview.prepared == nil && library.scorePreview.pageOwner.plan == nil)
    #expect(library.scorePreview.targetSpreadIndex == 0)
    lifecycle.phase = .active
    try await Task.sleep(for: .milliseconds(200))
    #expect(!library.scorePreview.isOpen)
    library.confirmFolio(entry.id)
    await TestAsyncWait.until("active scene explicit reopen", timeout: .seconds(30)) { if case .ready = library.scorePreview.state { return true }; return false }
    library.scorePreview.close()
    #expect(library.selectedEntryID == entry.id)
    #expect(library.scorePreview.prepared == nil && library.scorePreview.pageOwner.plan == nil)
    library.confirmFolio(entry.id)
    await TestAsyncWait.until("production reopened score", timeout: .seconds(30)) { if case .ready = library.scorePreview.state { return true }; return false }
    let reopened = try #require(library.scorePreview.pageOwner.plan)
    let plansMatch = reopened == plan
    #expect(plansMatch)
    #expect(library.scorePreview.targetSpreadIndex == 0)
}

@MainActor
@Observable
private final class PreviewNativeLifecycle {
    var phase: ScenePhase = .active
}

private struct PreviewNativeRoot: View {
    let graph: LiveAppGraph
    let lifecycle: PreviewNativeLifecycle

    var body: some View {
        LibraryWindowRootView(appState: graph.appState, songLibraryViewModel: graph.songLibraryViewModel, practiceLaunchViewModel: graph.practiceLaunchViewModel, diagnosticsViewModel: graph.diagnosticsViewModel)
            .environment(graph.pianoSetupCoordinator)
            .environment(\.scenePhase, lifecycle.phase)
    }
}
