import simd

enum TrackedHandJoint: CaseIterable, Hashable {
    case forearmArm
    case forearmWrist
    case wrist
    case thumbKnuckle
    case thumbIntermediateBase
    case thumbIntermediateTip
    case thumbTip
    case indexFingerMetacarpal
    case indexFingerKnuckle
    case indexFingerIntermediateBase
    case indexFingerIntermediateTip
    case indexFingerTip
    case middleFingerMetacarpal
    case middleFingerKnuckle
    case middleFingerIntermediateBase
    case middleFingerIntermediateTip
    case middleFingerTip
    case ringFingerMetacarpal
    case ringFingerKnuckle
    case ringFingerIntermediateBase
    case ringFingerIntermediateTip
    case ringFingerTip
    case littleFingerMetacarpal
    case littleFingerKnuckle
    case littleFingerIntermediateBase
    case littleFingerIntermediateTip
    case littleFingerTip

    static let fingerChains: [[Self]] = [
        [.thumbKnuckle, .thumbIntermediateBase, .thumbIntermediateTip, .thumbTip],
        [.indexFingerMetacarpal, .indexFingerKnuckle, .indexFingerIntermediateBase, .indexFingerIntermediateTip, .indexFingerTip],
        [.middleFingerMetacarpal, .middleFingerKnuckle, .middleFingerIntermediateBase, .middleFingerIntermediateTip, .middleFingerTip],
        [.ringFingerMetacarpal, .ringFingerKnuckle, .ringFingerIntermediateBase, .ringFingerIntermediateTip, .ringFingerTip],
        [.littleFingerMetacarpal, .littleFingerKnuckle, .littleFingerIntermediateBase, .littleFingerIntermediateTip, .littleFingerTip],
    ]

    static let palmJoints: [Self] = [
        .wrist,
        .thumbKnuckle,
        .indexFingerMetacarpal,
        .middleFingerMetacarpal,
        .ringFingerMetacarpal,
        .littleFingerMetacarpal,
    ]

    static let renderingJoints = Set(palmJoints + fingerChains.flatMap { $0 })
}

struct TrackedHandSkeleton: Equatable {
    var isTracked: Bool
    var joints: [TrackedHandJoint: SIMD3<Float>]

    init(
        isTracked: Bool = false,
        joints: [TrackedHandJoint: SIMD3<Float>] = [:]
    ) {
        self.isTracked = isTracked
        self.joints = joints
    }

    var isRenderable: Bool {
        isTracked && TrackedHandJoint.renderingJoints.allSatisfy { joints[$0] != nil }
    }

    subscript(_ joint: TrackedHandJoint) -> SIMD3<Float>? {
        joints[joint]
    }
}

struct HandSkeletonSnapshot: Equatable {
    static let empty = HandSkeletonSnapshot()

    var left: TrackedHandSkeleton
    var right: TrackedHandSkeleton

    init(
        left: TrackedHandSkeleton = TrackedHandSkeleton(),
        right: TrackedHandSkeleton = TrackedHandSkeleton()
    ) {
        self.left = left
        self.right = right
    }

    subscript(hand: TrackedHandSide) -> TrackedHandSkeleton {
        get {
            switch hand {
            case .left: left
            case .right: right
            }
        }
        set {
            switch hand {
            case .left: left = newValue
            case .right: right = newValue
            }
        }
    }
}
