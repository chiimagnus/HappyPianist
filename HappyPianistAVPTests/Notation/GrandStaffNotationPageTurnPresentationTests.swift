import CryptoKit
import Foundation
import MusicXML
@testable import Notation
import Observation
import Practice
import SwiftUI
import Testing
import UIKit
@testable import HappyPianistAVP

@Test
@MainActor
func pageTurnLiveSurfacesEndAtExactUprightTargetInBothDirections() throws {
    let plan = try turnPresentationPlan()
    #expect(plan.spreadCount >= 3)
    for (source, target) in [(0, 1), (1, 0)] {
        let transition = GrandStaffNotationPageTurnState.Transition(identity: plan.turnIdentity, generation: 1, source: source, target: target)
        let end = ImageRenderer(content: GrandStaffNotationPageTurnView(plan: plan, transition: transition, staffSpace: 7, overlay: .empty, practiceHandMode: .both, annotations: [], progress: 1))
        let stable = ImageRenderer(content: GrandStaffNotationPageTurnView(plan: plan, transition: .init(identity: plan.turnIdentity, generation: 2, source: target, target: target), staffSpace: 7, overlay: .empty, practiceHandMode: .both, annotations: [], progress: 0))
        let endImage = try #require(end.uiImage?.pngData())
        let stableImage = try #require(stable.uiImage?.pngData())
        #expect(endImage == stableImage)
        for progress in [0.0, 0.25, 0.75] {
            let frame = ImageRenderer(content: GrandStaffNotationPageTurnView(plan: plan, transition: transition, staffSpace: 7, overlay: .empty, practiceHandMode: .both, annotations: [], progress: progress))
            #expect(frame.cgImage != nil)
        }
    }
}

extension NativeBookWindowTests {
    @Test
    @MainActor
    func nativeCurledPaperRendersBothDirectionsAndKeepsLiveFacesUpright() async throws {
        let plan = try turnPresentationPlan()
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = try #require(scene.windows.first { $0.isKeyWindow })
        let original = window.rootViewController
        defer { window.rootViewController = original }
        func content(source: Int, target: Int, progress: Double) -> some View {
            let transition = GrandStaffNotationPageTurnState.Transition(identity: plan.turnIdentity, generation: 1, source: source, target: target)
            return GrandStaffNotationPageTurnView(plan: plan, transition: transition, staffSpace: min(window.bounds.width / plan.geometry.spreadWidth, window.bounds.height / plan.geometry.height) * 0.8, overlay: .empty, practiceHandMode: .both, annotations: [], progress: progress)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        let controller = UIHostingController(rootView: content(source: 0, target: 1, progress: 0))
        window.rootViewController = controller
        for (source, target) in [(0, 1), (1, 0)] {
            var images: Set<String> = []
            for progress in [0.0, 0.25, 0.5, 0.75, 1.0] {
                controller.rootView = content(source: source, target: target, progress: progress)
                try await Task.sleep(for: .milliseconds(200))
                let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                    #expect(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
                }
                let data = try #require(image.pngData())
                images.insert(SHA256.hash(data: data).description)
                Attachment.record(data, named: "curl-\(source)-to-\(target)-\(progress).png")
            }
            #expect(images.count == 5)
        }
    }

    @Test
    @MainActor
    func nativeSharedSpreadActuallyAnimatesAndRapidNavigationConvergesInExistingWindow() async throws {
        let plan = try turnPresentationPlan()
        let navigation = TurnNativeNavigation()
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = try #require(scene.windows.first { $0.isKeyWindow })
        let original = window.rootViewController
        defer { window.rootViewController = original }
        let controller = UIHostingController(rootView: TurnNativeRoot(plan: plan, navigation: navigation))
        window.rootViewController = controller
        try await Task.sleep(for: .seconds(1))
        navigation.target = 1
        try await Task.sleep(for: .milliseconds(80))
        let early = try windowFrame(window)
        try await Task.sleep(for: .milliseconds(220))
        let middle = try windowFrame(window)
        try await Task.sleep(for: .milliseconds(650))
        let end = try windowFrame(window)
        #expect(early != middle)
        #expect(middle != end)
        navigation.target = 0
        try await Task.sleep(for: .milliseconds(80))
        navigation.target = 2
        try await Task.sleep(for: .milliseconds(800))
        let finalJump = try windowFrame(window)
        try await Task.sleep(for: .milliseconds(150))
        #expect(finalJump == (try windowFrame(window)))
    }

}

@MainActor
private func windowFrame(_ window: UIWindow) throws -> String {
    let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
        #expect(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
    }
    return SHA256.hash(data: try #require(image.pngData())).description
}

@MainActor
private func turnPresentationPlan() throws -> GrandStaffNotationPagePlan {
    let bars = (1...48).map { measure in
        let notes = (0..<8).map { note in "<note><pitch><step>\(note.isMultiple(of: 2) ? "C" : "G")</step><octave>\(measure.isMultiple(of: 2) ? 4 : 5)</octave></pitch><duration>1</duration><type>eighth</type><staff>1</staff></note>" }.joined()
        return "<measure number=\"\(measure)\">\(measure == 1 ? "<attributes><divisions>2</divisions><staves>2</staves><time><beats>4</beats><beat-type>4</beat-type></time></attributes>" : "")\(notes)</measure>"
    }.joined()
    let source = try MusicXMLParser().parse(data: Data("<score-partwise><part-list><score-part id=\"P1\"><part-name>Piano</part-name></score-part></part-list><part id=\"P1\">\(bars)</part></score-partwise>".utf8))
    let projection = ScoreNotationProjection(plan: makeTestScorePerformancePlan(from: source), sourceScore: source)
    return try GrandStaffNotationPaginationService().makePlan(score: makeNotationScoreFixture(projection: projection, measureSpans: source.measures))
}

@MainActor
@Observable
private final class TurnNativeNavigation {
    var target = 0
}

private struct TurnNativeRoot: View {
    let plan: GrandStaffNotationPagePlan
    let navigation: TurnNativeNavigation
    var body: some View {
        GrandStaffNotationSpreadView(plan: plan, targetIndex: navigation.target)
            .padding(30)
    }
}
