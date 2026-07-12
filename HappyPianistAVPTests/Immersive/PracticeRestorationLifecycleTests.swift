@testable import HappyPianistAVP
import Foundation
import RealityKit
import Testing

@Test @MainActor
func restorationRendererIgnoresSummaryEvents() {
    let renderer = PracticeRestorationEffectRenderer()
    let parent = Entity()
    renderer.update(event: nil, parent: parent, reduceMotion: false)
    #expect(renderer.activeEffectCount == 0)
}

@Test @MainActor
func restorationResetCannotBeRevivedByCancelledTask() async {
    let renderer = PracticeRestorationEffectRenderer()
    let parent = Entity()
    let event = PracticeFeedbackEvent(
        identity: PracticeSongIdentity(songID: UUID(), scoreRevision: "r"),
        sessionGeneration: 1,
        roundGeneration: 1,
        sequence: 1,
        sourceMeasureID: nil,
        kind: .measureStable
    )
    renderer.update(event: event, parent: parent, reduceMotion: true)
    renderer.reset()
    await Task.yield()
    #expect(renderer.activeEffectCount == 0)
    #expect(parent.children.isEmpty)
}
