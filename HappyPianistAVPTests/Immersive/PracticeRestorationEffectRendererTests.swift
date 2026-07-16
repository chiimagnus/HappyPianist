import Foundation
@testable import HappyPianistAVP
import RealityKit
import Testing

@Test @MainActor
func restorationRendererResetRemovesEffect() {
    let renderer = PracticeRestorationEffectRenderer(sleeper: LongRestorationSleeper())
    let event = PracticeFeedbackEvent(
        sequence: 1,
        sourceMeasureID: nil,
        kind: .measureStable
    )
    let parent = Entity()
    renderer.update(event: event, parent: parent, reduceMotion: true)
    #expect(parent.children.count == 1)
    renderer.reset()
    #expect(parent.children.isEmpty)
}

private struct LongRestorationSleeper: SleeperProtocol {
    func sleep(for _: Duration) async throws {
        try await Task.sleep(for: .seconds(60))
    }
}
