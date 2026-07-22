import Foundation
@testable import HappyPianistAVP
import RealityKit
import Testing

@Test @MainActor
func restorationRendererIgnoresSummaryEvents() {
    let renderer = PracticeRestorationEffectRenderer()
    let parent = Entity()
    renderer.update(event: nil, parent: parent, reduceMotion: false)
    #expect(parent.children.isEmpty)
}

@Test @MainActor
func restorationResetCannotBeRevivedByCancelledTask() async {
    let renderer = PracticeRestorationEffectRenderer()
    let parent = Entity()
    let event = PracticeFeedbackEvent(
        sequence: 1,
        sourceMeasureID: nil,
        kind: .measurePitchStepsStable
    )
    renderer.update(event: event, parent: parent, reduceMotion: true)
    renderer.reset()
    await Task.yield()
    #expect(parent.children.isEmpty)
}

@Test @MainActor
func clearingFeedbackEventRemovesRestorationEffect() async {
    let renderer = PracticeRestorationEffectRenderer()
    let parent = Entity()
    let event = PracticeFeedbackEvent(
        sequence: 1,
        sourceMeasureID: nil,
        kind: .measurePitchStepsStable
    )
    renderer.update(event: event, parent: parent, reduceMotion: false)
    renderer.update(event: nil, parent: parent, reduceMotion: false)
    await Task.yield()
    #expect(parent.children.isEmpty)
}
