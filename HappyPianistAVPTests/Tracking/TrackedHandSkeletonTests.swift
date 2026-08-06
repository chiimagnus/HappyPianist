import simd
@testable import HappyPianistAVP
import Testing

@Test
func trackedHandJointDescribesAllARKitHandJoints() {
    #expect(TrackedHandJoint.allCases.count == 27)
}

@Test
func renderableSkeletonRequiresTrackingAndEveryRenderedJoint() {
    let completeJoints = Dictionary(
        uniqueKeysWithValues: TrackedHandJoint.renderingJoints.map {
            ($0, SIMD3<Float>(repeating: Float($0.hashValue)))
        }
    )

    #expect(TrackedHandSkeleton(isTracked: false, joints: completeJoints).isRenderable == false)
    #expect(TrackedHandSkeleton(isTracked: true, joints: completeJoints).isRenderable)

    var incompleteJoints = completeJoints
    incompleteJoints.removeValue(forKey: .indexFingerTip)
    #expect(TrackedHandSkeleton(isTracked: true, joints: incompleteJoints).isRenderable == false)
}

@Test
func handSkeletonSnapshotKeepsHandsIndependent() {
    var snapshot = HandSkeletonSnapshot()
    snapshot[.left] = TrackedHandSkeleton(isTracked: true)

    #expect(snapshot.left.isTracked)
    #expect(snapshot.right.isTracked == false)
}
