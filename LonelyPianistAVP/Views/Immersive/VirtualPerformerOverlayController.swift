import RealityKit
import simd
import SwiftUI

@MainActor
final class VirtualPerformerOverlayController {
    private var rootEntity = Entity()
    private var hasAttachedRoot = false
    private var performerRootEntity: Entity?
    private var performerVisualRootEntity: Entity?
    private var headEntity: Entity?
    private var headRestTransform: Transform?
    private var leftHandEntity: Entity?
    private var leftHandRestTransform: Transform?
    private var rightHandEntity: Entity?
    private var rightHandRestTransform: Transform?
    private var handAnimationTask: Task<Void, Never>?
    private var latestSchedule: [PracticeSequencerMIDIEvent] = []
    private var wasPerforming = false
    private var nextNoteUsesLeftHand = true

    func update(
        isEnabled: Bool,
        isPerforming: Bool,
        keyboardGeometry: PianoKeyboardGeometry?,
        cameraWorldPosition: SIMD3<Float>? = nil,
        performanceSchedule: [PracticeSequencerMIDIEvent] = [],
        content: RealityViewContent?
    ) {
        if hasAttachedRoot == false, let content {
            content.add(rootEntity)
            hasAttachedRoot = true
        }

        guard isEnabled, let keyboardGeometry else {
            clearPerformer()
            return
        }

        showPerformer(geometry: keyboardGeometry, cameraWorldPosition: cameraWorldPosition)

        if wasPerforming != isPerforming {
            animateHead(isPerforming: isPerforming)
            if isPerforming == false {
                stopHandAnimation()
                resetHandsToRest(animated: true)
            }
            wasPerforming = isPerforming
        }

        if isPerforming {
            updateHandAnimationIfNeeded(schedule: performanceSchedule)
        }
    }

    private func showPerformer(geometry: PianoKeyboardGeometry, cameraWorldPosition: SIMD3<Float>?) {
        if performerRootEntity == nil {
            let performerRoot = makePerformerRootEntity()
            rootEntity.addChild(performerRoot)
            performerRootEntity = performerRoot
        }

        guard let performerRootEntity else { return }

        let totalLength = VirtualPianoKeyGeometryService.totalKeyboardLengthMeters
        let keyDepth = VirtualPianoKeyGeometryService.whiteKeyDepthMeters
        let keyboardCenterLocal = SIMD3<Float>(totalLength / 2, 0, -keyDepth / 2)

        let worldFromKeyboard = geometry.frame.worldFromKeyboard
        let xAxisWorld = SIMD3<Float>(
            worldFromKeyboard.columns.0.x,
            worldFromKeyboard.columns.0.y,
            worldFromKeyboard.columns.0.z
        )
        let yAxisWorld = SIMD3<Float>(
            worldFromKeyboard.columns.1.x,
            worldFromKeyboard.columns.1.y,
            worldFromKeyboard.columns.1.z
        )
        let zAxisWorld = SIMD3<Float>(
            worldFromKeyboard.columns.2.x,
            worldFromKeyboard.columns.2.y,
            worldFromKeyboard.columns.2.z
        )
        let originWorld = SIMD3<Float>(
            worldFromKeyboard.columns.3.x,
            worldFromKeyboard.columns.3.y,
            worldFromKeyboard.columns.3.z
        )
        let keyboardCenterWorld = originWorld
            + xAxisWorld * keyboardCenterLocal.x
            + yAxisWorld * keyboardCenterLocal.y
            + zAxisWorld * keyboardCenterLocal.z

        let upAxisWorld = simd_normalize(yAxisWorld)
        let rightOnPlaneWorld: SIMD3<Float> = {
            let rightOnPlane = xAxisWorld - upAxisWorld * simd_dot(xAxisWorld, upAxisWorld)
            guard simd_length(rightOnPlane) > 0.0001 else { return SIMD3<Float>(1, 0, 0) }
            return simd_normalize(rightOnPlane)
        }()
        let forwardOnPlaneWorld = simd_normalize(simd_cross(rightOnPlaneWorld, upAxisWorld))
        let shouldFlipFacing: Bool = {
            guard let cameraWorldPosition else { return false }
            let toCameraWorld = cameraWorldPosition - keyboardCenterWorld
            let toCameraOnPlane = toCameraWorld - upAxisWorld * simd_dot(toCameraWorld, upAxisWorld)
            guard simd_length(toCameraOnPlane) > 0.0001 else { return false }
            return simd_dot(forwardOnPlaneWorld, toCameraOnPlane) < 0
        }()

        let offsetRightMeters: Float = totalLength * 0.6
        let offsetForwardMeters: Float = keyDepth * 0.8
        let offsetUpMeters: Float = 0.0

        let performerPositionWorld = keyboardCenterWorld
            + rightOnPlaneWorld * offsetRightMeters
            - forwardOnPlaneWorld * offsetForwardMeters
            + upAxisWorld * offsetUpMeters

        let performerWorldFromRoot = simd_float4x4(columns: (
            SIMD4<Float>(rightOnPlaneWorld, 0),
            SIMD4<Float>(upAxisWorld, 0),
            SIMD4<Float>(forwardOnPlaneWorld, 0),
            SIMD4<Float>(performerPositionWorld, 1)
        ))

        performerRootEntity.transform = Transform(matrix: performerWorldFromRoot)
        let baselineFacingAngle: Float = .pi
        performerVisualRootEntity?.orientation = simd_quatf(
            angle: baselineFacingAngle + (shouldFlipFacing ? .pi : 0),
            axis: [0, 1, 0]
        )
    }

    private func clearPerformer() {
        stopHandAnimation()
        performerRootEntity?.removeFromParent()
        performerRootEntity = nil
        performerVisualRootEntity = nil
        headEntity = nil
        headRestTransform = nil
        leftHandEntity = nil
        leftHandRestTransform = nil
        rightHandEntity = nil
        rightHandRestTransform = nil
        latestSchedule = []
        wasPerforming = false
    }

    private func makePerformerRootEntity() -> Entity {
        let root = Entity()
        let visualRoot = Entity()
        root.addChild(visualRoot)
        performerVisualRootEntity = visualRoot
        visualRoot.addChild(makeTinyPianoEntity())
        visualRoot.addChild(makePerformerEntity())
        return root
    }

    private func makePerformerEntity() -> Entity {
        let performer = Entity()

        let bodyColor = SimpleMaterial(color: UIColor.orange, isMetallic: false)
        let accentColor = SimpleMaterial(color: UIColor.white, isMetallic: false)

        let head = makeHeadEntity(bodyColor: bodyColor)
        head.position = [0, 0.52, 0]
        performer.addChild(head)
        headEntity = head
        headRestTransform = head.transform

        let torso = ModelEntity(mesh: .generateCylinder(height: 0.32, radius: 0.07), materials: [bodyColor])
        torso.position = [0, 0.32, 0]
        performer.addChild(torso)

        let leftArm = ModelEntity(mesh: .generateCylinder(height: 0.24, radius: 0.03), materials: [bodyColor])
        leftArm.position = [-0.14, 0.34, 0]
        leftArm.transform.rotation = simd_quatf(angle: .pi / 2.6, axis: [0, 0, 1])
        performer.addChild(leftArm)

        let rightArm = ModelEntity(mesh: .generateCylinder(height: 0.24, radius: 0.03), materials: [bodyColor])
        rightArm.position = [0.14, 0.34, 0]
        rightArm.transform.rotation = simd_quatf(angle: -.pi / 2.6, axis: [0, 0, 1])
        performer.addChild(rightArm)

        let leftHand = ModelEntity(mesh: .generateSphere(radius: 0.035), materials: [accentColor])
        leftHand.position = [-0.24, 0.26, 0.03]
        performer.addChild(leftHand)
        leftHandEntity = leftHand
        leftHandRestTransform = leftHand.transform

        let rightHand = ModelEntity(mesh: .generateSphere(radius: 0.035), materials: [accentColor])
        rightHand.position = [0.24, 0.26, 0.03]
        performer.addChild(rightHand)
        rightHandEntity = rightHand
        rightHandRestTransform = rightHand.transform

        let leftLeg = ModelEntity(mesh: .generateCylinder(height: 0.28, radius: 0.035), materials: [bodyColor])
        leftLeg.position = [-0.06, 0.12, 0]
        performer.addChild(leftLeg)

        let rightLeg = ModelEntity(mesh: .generateCylinder(height: 0.28, radius: 0.035), materials: [bodyColor])
        rightLeg.position = [0.06, 0.12, 0]
        performer.addChild(rightLeg)

        return performer
    }

    private func animateHead(isPerforming: Bool) {
        guard let headEntity else { return }
        let baseTransform = headRestTransform ?? headEntity.transform
        var targetTransform = baseTransform
        targetTransform.rotation = simd_quatf(angle: isPerforming ? 0.6 : 0.0, axis: [1, 0, 0])
        _ = headEntity.move(
            to: targetTransform,
            relativeTo: headEntity.parent,
            duration: 0.25,
            timingFunction: .easeInOut
        )
    }

    private func updateHandAnimationIfNeeded(schedule: [PracticeSequencerMIDIEvent]) {
        guard schedule != latestSchedule else { return }
        latestSchedule = schedule
        startHandAnimation(schedule: schedule)
    }

    private func startHandAnimation(schedule: [PracticeSequencerMIDIEvent]) {
        stopHandAnimation()
        resetHandsToRest(animated: false)
        nextNoteUsesLeftHand = true

        let sortedSchedule = schedule.sorted { lhs, rhs in
            if lhs.timeSeconds != rhs.timeSeconds { return lhs.timeSeconds < rhs.timeSeconds }
            return eventPriority(lhs.kind) < eventPriority(rhs.kind)
        }

        handAnimationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var previousTimeSeconds: TimeInterval = 0
            for event in sortedSchedule {
                guard Task.isCancelled == false else { return }
                let delaySeconds = max(0, event.timeSeconds - previousTimeSeconds)
                if delaySeconds > 0 {
                    try? await Task.sleep(for: .seconds(delaySeconds))
                }
                guard Task.isCancelled == false else { return }

                switch event.kind {
                    case let .noteOn(_, velocity):
                        self.animateHandDown(velocity: velocity)
                    case .noteOff:
                        self.resetHandsToRest(animated: true)
                    case .controlChange:
                        break
                }
                previousTimeSeconds = event.timeSeconds
            }
        }
    }

    private func stopHandAnimation() {
        handAnimationTask?.cancel()
        handAnimationTask = nil
    }

    private func animateHandDown(velocity: UInt8) {
        let handEntity = nextNoteUsesLeftHand ? leftHandEntity : rightHandEntity
        let baseTransform = nextNoteUsesLeftHand ? leftHandRestTransform : rightHandRestTransform
        nextNoteUsesLeftHand.toggle()

        guard let handEntity, let baseTransform else { return }

        var targetTransform = baseTransform
        let normalizedVelocity = min(1, max(0, Float(velocity) / 127))
        let depthMeters: Float = 0.06 + normalizedVelocity * 0.02
        targetTransform.translation.y = baseTransform.translation.y - depthMeters

        _ = handEntity.move(
            to: targetTransform,
            relativeTo: handEntity.parent,
            duration: 0.06,
            timingFunction: .easeInOut
        )
    }

    private func resetHandsToRest(animated: Bool) {
        guard let leftHandEntity, let leftHandRestTransform,
              let rightHandEntity, let rightHandRestTransform
        else { return }

        if animated == false {
            leftHandEntity.transform = leftHandRestTransform
            rightHandEntity.transform = rightHandRestTransform
            return
        }

        _ = leftHandEntity.move(
            to: leftHandRestTransform,
            relativeTo: leftHandEntity.parent,
            duration: 0.08,
            timingFunction: .easeInOut
        )
        _ = rightHandEntity.move(
            to: rightHandRestTransform,
            relativeTo: rightHandEntity.parent,
            duration: 0.08,
            timingFunction: .easeInOut
        )
    }

    private func eventPriority(_ kind: PracticeSequencerMIDIEvent.Kind) -> Int {
        switch kind {
            case .controlChange:
                0
            case .noteOff:
                1
            case .noteOn:
                2
        }
    }

    private func makeHeadEntity(bodyColor: SimpleMaterial) -> Entity {
        let root = Entity()

        let segmentCount = 16
        let ringRadius: Float = 0.095
        let segmentHeight: Float = 0.015
        let segmentRadius: Float = 0.01

        for index in 0 ..< segmentCount {
            let angle = (Float(index) / Float(segmentCount)) * (2 * .pi)
            let x = cos(angle) * ringRadius
            let z = sin(angle) * ringRadius

            let segment = ModelEntity(
                mesh: .generateCylinder(height: segmentHeight, radius: segmentRadius),
                materials: [bodyColor]
            )
            segment.position = [x, 0, z]
            segment.transform.rotation = simd_quatf(angle: angle, axis: [0, 1, 0])
            root.addChild(segment)
        }

        return root
    }

    private func makeTinyPianoEntity() -> Entity {
        let piano = Entity()

        let caseMaterial = SimpleMaterial(color: UIColor.darkGray, isMetallic: false)
        let keyMaterial = SimpleMaterial(color: UIColor.lightGray, isMetallic: false)

        let body = ModelEntity(mesh: .generateBox(size: [0.55, 0.08, 0.26]), materials: [caseMaterial])
        body.position = [0, 0.40, 0.12]
        piano.addChild(body)

        let keys = ModelEntity(mesh: .generateBox(size: [0.52, 0.02, 0.18]), materials: [keyMaterial])
        keys.position = [0, 0.45, 0.05]
        piano.addChild(keys)

        return piano
    }
}
