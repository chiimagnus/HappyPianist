@testable import HappyPianistAVP
import RealityKit
import Testing

@Test @MainActor
func restorationRendererIgnoresSummaryEvents() {
    let renderer = PracticeRestorationEffectRenderer()
    let parent = Entity()
    renderer.update(event: nil, parent: parent, reduceMotion: false)
    #expect(renderer.activeEffectCount == 0)
}
