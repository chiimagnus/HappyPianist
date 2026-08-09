@testable import HappyPianistAVP
@testable import Practice
import RealityKit
import simd
import Testing

@MainActor
@Test
func handRigLoadsPackaged21JointAssetAndAppliesClipFrame() async throws {
    let rig = try await PackagedPianoDemonstrationHandRigLoader().load(hand: .right)
    let rootTransform = PianoHandMotionClip.RootTransform(
        translation: [0.12, 0.045, -0.02],
        rotation: simd_quatf(angle: 0.05, axis: [0, 1, 0]).vector
    )
    var rotations = Array(repeating: SIMD4<Float>(0, 0, 0, 1), count: 21)
    rotations[9] = simd_quatf(angle: 0.25, axis: [1, 0, 0]).vector
    let frame = PianoHandMotionClip.Frame(
        timeSeconds: 0,
        rootTransform: rootTransform,
        jointRotations: rotations
    )

    #expect(rig.jointCount == 21)
    #expect(rig.rootEntity.children.count == 1)
    let skinnedModel = try #require(rig.rootEntity.firstSkinnedModelEntity())
    let restTranslations = skinnedModel.jointTransforms.map(\.translation)
    rig.apply(frame: frame)
    #expect(rig.rootEntity.isEnabled)
    #expect(simd_distance(rig.rootEntity.position, rootTransform.translation) < 0.0001)
    #expect(abs(simd_dot(
        rig.rootEntity.transform.rotation.vector,
        rootTransform.rotation
    )) > 0.999)
    #expect(zip(restTranslations, skinnedModel.jointTransforms.map(\.translation)).allSatisfy {
        simd_distance($0, $1) < 0.000_001
    })

    rig.hide()
    #expect(rig.rootEntity.isEnabled == false)
}
