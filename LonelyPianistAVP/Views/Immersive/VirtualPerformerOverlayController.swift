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
    private var performerPianoEntity: Entity?
    private var headEntity: Entity?
    private var headRestTransform: Transform?
    private var leftArmRootEntity: Entity?
    private var leftArmRestTransform: Transform?
    private var rightArmRootEntity: Entity?
    private var rightArmRestTransform: Transform?
    private var handAnimationTask: Task<Void, Never>?
    private var leftArmPulseTask: Task<Void, Never>?
    private var rightArmPulseTask: Task<Void, Never>?
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
                resetArmsToRest(animated: true)
            }
            wasPerforming = isPerforming
        }

        if isPerforming {
            updateHandAnimationIfNeeded(schedule: performanceSchedule)
        }
    }

    private func showPerformer(geometry: PianoKeyboardGeometry, cameraWorldPosition: SIMD3<Float>?) {
        if performerRootEntity == nil {
            let performerRoot = makePerformerRootEntity(geometry: geometry)
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
        let offsetRightMeters: Float = totalLength * 1.05
        let offsetForwardMeters: Float = keyDepth * 3.2
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
        performerPianoEntity = nil
        headEntity = nil
        headRestTransform = nil
        leftArmRootEntity = nil
        leftArmRestTransform = nil
        rightArmRootEntity = nil
        rightArmRestTransform = nil
        latestSchedule = []
        wasPerforming = false
    }

    private func makePerformerRootEntity(geometry: PianoKeyboardGeometry) -> Entity {
        let root = Entity()
        let visualRoot = Entity()
        root.addChild(visualRoot)
        performerVisualRootEntity = visualRoot
        let piano = makePerformerPianoEntity(geometry: geometry)
        visualRoot.addChild(piano)
        performerPianoEntity = piano
        visualRoot.addChild(makePerformerEntity())
        return root
    }

    private func makePerformerEntity() -> Entity {
        let performer = Entity()

        let bodyColor = SimpleMaterial(color: UIColor.orange, isMetallic: false)

        let head = makeHeadEntity(bodyColor: bodyColor)
        head.position = [0, 0.52, 0]
        performer.addChild(head)
        headEntity = head
        headRestTransform = head.transform

        let torso = makeCapsuleEntity(height: 0.34, radius: 0.075, material: bodyColor)
        torso.position = [0, 0.32, 0]
        performer.addChild(torso)

        let armLength: Float = 0.28
        let armRadius: Float = 0.03
        let shoulderY: Float = 0.40
        let shoulderX: Float = 0.13

        let leftArmRoot = Entity()
        leftArmRoot.position = [-shoulderX, shoulderY, 0]
        performer.addChild(leftArmRoot)
        leftArmRootEntity = leftArmRoot
        leftArmRestTransform = leftArmRoot.transform

        let leftArmGeometry = makeCapsuleEntity(height: armLength, radius: armRadius, material: bodyColor)
        leftArmGeometry.position = [0, -armLength / 2, 0]
        leftArmRoot.addChild(leftArmGeometry)

        let rightArmRoot = Entity()
        rightArmRoot.position = [shoulderX, shoulderY, 0]
        performer.addChild(rightArmRoot)
        rightArmRootEntity = rightArmRoot
        rightArmRestTransform = rightArmRoot.transform

        let rightArmGeometry = makeCapsuleEntity(height: armLength, radius: armRadius, material: bodyColor)
        rightArmGeometry.position = [0, -armLength / 2, 0]
        rightArmRoot.addChild(rightArmGeometry)

        let leftLeg = makeCapsuleEntity(height: 0.30, radius: 0.037, material: bodyColor)
        leftLeg.position = [-0.06, 0.12, 0]
        performer.addChild(leftLeg)

        let rightLeg = makeCapsuleEntity(height: 0.30, radius: 0.037, material: bodyColor)
        rightLeg.position = [0.06, 0.12, 0]
        performer.addChild(rightLeg)

        return performer
    }

    private func makeCapsuleEntity(height: Float, radius: Float, material: SimpleMaterial) -> Entity {
        let root = Entity()
        let cylinderHeight = max(0.001, height - radius * 2)
        let cylinder = ModelEntity(mesh: .generateCylinder(height: cylinderHeight, radius: radius), materials: [material])
        root.addChild(cylinder)

        let capMesh = MeshResource.generateSphere(radius: radius)
        let top = ModelEntity(mesh: capMesh, materials: [material])
        top.position.y = cylinderHeight / 2
        root.addChild(top)

        let bottom = ModelEntity(mesh: capMesh, materials: [material])
        bottom.position.y = -cylinderHeight / 2
        root.addChild(bottom)

        return root
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
        resetArmsToRest(animated: false)
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
                        self.animateArmSwing(velocity: velocity)
                    case .noteOff:
                        break
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
        leftArmPulseTask?.cancel()
        leftArmPulseTask = nil
        rightArmPulseTask?.cancel()
        rightArmPulseTask = nil
    }

    private func animateArmSwing(velocity: UInt8) {
        let isLeftArm = nextNoteUsesLeftHand
        let armEntity = isLeftArm ? leftArmRootEntity : rightArmRootEntity
        let baseTransform = isLeftArm ? leftArmRestTransform : rightArmRestTransform
        nextNoteUsesLeftHand.toggle()

        guard let armEntity, let baseTransform else { return }

        let normalizedVelocity = min(1, max(0, Float(velocity) / 127))
        let angleRadians: Float = -0.5 - normalizedVelocity * 0.6
        var targetTransform = baseTransform
        targetTransform.rotation = simd_quatf(angle: angleRadians, axis: [1, 0, 0])

        if isLeftArm {
            leftArmPulseTask?.cancel()
            leftArmPulseTask = Task { @MainActor in
                armEntity.transform = baseTransform
                _ = armEntity.move(
                    to: targetTransform,
                    relativeTo: armEntity.parent,
                    duration: 0.05,
                    timingFunction: .easeInOut
                )
                try? await Task.sleep(for: .milliseconds(90))
                _ = armEntity.move(
                    to: baseTransform,
                    relativeTo: armEntity.parent,
                    duration: 0.08,
                    timingFunction: .easeInOut
                )
            }
        } else {
            rightArmPulseTask?.cancel()
            rightArmPulseTask = Task { @MainActor in
                armEntity.transform = baseTransform
                _ = armEntity.move(
                    to: targetTransform,
                    relativeTo: armEntity.parent,
                    duration: 0.05,
                    timingFunction: .easeInOut
                )
                try? await Task.sleep(for: .milliseconds(90))
                _ = armEntity.move(
                    to: baseTransform,
                    relativeTo: armEntity.parent,
                    duration: 0.08,
                    timingFunction: .easeInOut
                )
            }
        }
    }

    private func resetArmsToRest(animated: Bool) {
        guard let leftArmRootEntity, let leftArmRestTransform,
              let rightArmRootEntity, let rightArmRestTransform
        else { return }

        if animated == false {
            leftArmRootEntity.transform = leftArmRestTransform
            rightArmRootEntity.transform = rightArmRestTransform
            return
        }

        _ = leftArmRootEntity.move(
            to: leftArmRestTransform,
            relativeTo: leftArmRootEntity.parent,
            duration: 0.08,
            timingFunction: .easeInOut
        )
        _ = rightArmRootEntity.move(
            to: rightArmRestTransform,
            relativeTo: rightArmRootEntity.parent,
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
            extrusionDepth: 0.02,
            font: UIFont.systemFont(ofSize: 0.30, weight: .heavy),
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

    private func makePerformerPianoEntity(geometry: PianoKeyboardGeometry) -> Entity {
        let performerPianoScale: Float = 1.0

        let root = Entity()
        root.position = [0, 0.42, 0.48]
        root.scale = SIMD3<Float>(repeating: performerPianoScale)
        root.transform.rotation = simd_quatf(angle: .pi, axis: [0, 1, 0])

        let totalLength = VirtualPianoKeyGeometryService.totalKeyboardLengthMeters
        let keyDepth = VirtualPianoKeyGeometryService.whiteKeyDepthMeters
        let keyboardCenterLocal = SIMD3<Float>(totalLength / 2, 0, -keyDepth / 2)

        let keyboardRoot = Entity()
        keyboardRoot.position = -keyboardCenterLocal

        for key in geometry.keys {
            keyboardRoot.addChild(makeVirtualKeyEntity(for: key))
        }

        root.addChild(keyboardRoot)
        return root
    }

    private func makeVirtualKeyEntity(for key: PianoKeyGeometry) -> ModelEntity {
        let mesh = MeshResource.generateBox(size: key.localSize)
        let color: UIColor = key.kind == .white ? .white : .black
        var material = SimpleMaterial(color: color, isMetallic: false)
        material.roughness = 0.5

        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.position = key.localCenter
        return entity
    }
}
