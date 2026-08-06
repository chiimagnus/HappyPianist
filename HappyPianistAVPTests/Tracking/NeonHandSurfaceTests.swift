import simd
@testable import HappyPianistAVP
import Testing

@Test
func neonHandSurfaceProducesFixedValidTopology() throws {
    let geometry = try #require(NeonHandSurface.geometry(for: makeTrackedHandSkeleton()))

    #expect(geometry.positions.count == NeonHandSurface.vertexCount)
    #expect(geometry.normals.count == NeonHandSurface.vertexCount)
    #expect(NeonHandSurface.triangleIndices.count.isMultiple(of: 3))
    #expect(NeonHandSurface.triangleIndices.allSatisfy { $0 < UInt32(NeonHandSurface.vertexCount) })
    for position in geometry.positions {
        #expect(position.x.isFinite)
        #expect(position.y.isFinite)
        #expect(position.z.isFinite)
    }
}

@Test
func neonHandSurfaceRejectsMissingRenderedJoint() {
    var skeleton = makeTrackedHandSkeleton()
    skeleton.joints.removeValue(forKey: .ringFingerTip)

    #expect(NeonHandSurface.geometry(for: skeleton) == nil)
}

@Test
func neonHandSurfaceMovesWithJointPositions() throws {
    let initial = try #require(NeonHandSurface.geometry(for: makeTrackedHandSkeleton()))
    var movedSkeleton = makeTrackedHandSkeleton()
    movedSkeleton.joints[.indexFingerTip] = SIMD3<Float>(-0.030, 0.135, 0.018)
    let moved = try #require(NeonHandSurface.geometry(for: movedSkeleton))

    #expect(initial.positions != moved.positions)
}

private func makeTrackedHandSkeleton() -> TrackedHandSkeleton {
    var joints = Dictionary(
        uniqueKeysWithValues: TrackedHandJoint.allCases.map { ($0, SIMD3<Float>.zero) }
    )
    joints[.wrist] = [0, 0, 0]
    joints[.thumbKnuckle] = [-0.032, 0.020, 0]
    joints[.thumbIntermediateBase] = [-0.047, 0.035, 0.004]
    joints[.thumbIntermediateTip] = [-0.057, 0.048, 0.008]
    joints[.thumbTip] = [-0.065, 0.060, 0.012]
    addFinger(
        [.indexFingerMetacarpal, .indexFingerKnuckle, .indexFingerIntermediateBase, .indexFingerIntermediateTip, .indexFingerTip],
        startingAt: [-0.025, 0.026, 0],
        joints: &joints
    )
    addFinger(
        [.middleFingerMetacarpal, .middleFingerKnuckle, .middleFingerIntermediateBase, .middleFingerIntermediateTip, .middleFingerTip],
        startingAt: [0, 0.030, 0],
        joints: &joints
    )
    addFinger(
        [.ringFingerMetacarpal, .ringFingerKnuckle, .ringFingerIntermediateBase, .ringFingerIntermediateTip, .ringFingerTip],
        startingAt: [0.024, 0.027, 0],
        joints: &joints
    )
    addFinger(
        [.littleFingerMetacarpal, .littleFingerKnuckle, .littleFingerIntermediateBase, .littleFingerIntermediateTip, .littleFingerTip],
        startingAt: [0.044, 0.020, 0],
        joints: &joints
    )
    return TrackedHandSkeleton(isTracked: true, joints: joints)
}

private func addFinger(
    _ chain: [TrackedHandJoint],
    startingAt start: SIMD3<Float>,
    joints: inout [TrackedHandJoint: SIMD3<Float>]
) {
    for (index, joint) in chain.enumerated() {
        let position = start + SIMD3<Float>(0, Float(index) * 0.020, Float(index) * 0.002)
        joints[joint] = position
    }
}
