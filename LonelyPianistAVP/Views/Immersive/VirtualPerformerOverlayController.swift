import RealityKit
import simd
import SwiftUI
import UIKit

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
        let offsetRightMeters: Float = totalLength * 0.9
        let offsetForwardMeters: Float = keyDepth * 1.8
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
        guard let performerVisualRootEntity else { return }
        let toKeyboardWorld = keyboardCenterWorld - performerPositionWorld
        let toKeyboardOnPlane = toKeyboardWorld - upAxisWorld * simd_dot(toKeyboardWorld, upAxisWorld)
        guard simd_length(toKeyboardOnPlane) > 0.0001 else { return }
        let lookAtWorld = performerPositionWorld + toKeyboardOnPlane
        performerVisualRootEntity.look(
            at: lookAtWorld,
            from: performerPositionWorld,
            upVector: upAxisWorld,
            relativeTo: nil,
            forward: .positiveZ
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

        let mesh = MeshResource.generateText(
            "O",
            extrusionDepth: 0.018,
            font: UIFont.systemFont(ofSize: 0.22, weight: .heavy),
            containerFrame: .zero,
            alignment: .center,
            lineBreakMode: .byClipping
        )
        let ring = ModelEntity(mesh: mesh, materials: [bodyColor])
        let bounds = ring.visualBounds(relativeTo: nil)
        ring.position = -bounds.center
        root.addChild(ring)

        return root
    }
}
