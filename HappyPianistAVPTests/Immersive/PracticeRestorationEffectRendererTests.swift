import Foundation
import RealityKit
@testable import HappyPianistAVP
import Testing

@Test @MainActor
func restorationRendererResetRemovesEffect() {
    let renderer = PracticeRestorationEffectRenderer(sleeper: LongRestorationSleeper())
    let event = PracticeFeedbackEvent(
        identity: PracticeSongIdentity(songID: UUID(), scoreRevision: "r"),
        sessionGeneration: 1,
        roundGeneration: 1,
        sourceMeasureID: nil,
        kind: .measureStable
    )
    let parent = Entity()
    renderer.update(event: event, parent: parent, reduceMotion: true)
    #expect(renderer.activeEffectCount == 1)
    renderer.reset()
    #expect(renderer.activeEffectCount == 0)
    #expect(parent.children.isEmpty)
}

private struct LongRestorationSleeper: SleeperProtocol {
    func sleep(for _: Duration) async throws { try await Task.sleep(for: .seconds(60)) }
}
