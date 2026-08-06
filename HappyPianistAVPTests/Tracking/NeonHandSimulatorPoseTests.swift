import Testing

@testable import HappyPianistAVP

#if targetEnvironment(simulator)
    @Test
    func neonHandSimulatorPoseProvidesTwoRenderableHands() {
        let snapshot = NeonHandSimulatorPose.snapshot(phase: 0)

        #expect(snapshot.left.isRenderable)
        #expect(snapshot.right.isRenderable)
        #expect((snapshot.left[.wrist]?.x ?? 0) < 0)
        #expect((snapshot.right[.wrist]?.x ?? 0) > 0)
    }
#endif
