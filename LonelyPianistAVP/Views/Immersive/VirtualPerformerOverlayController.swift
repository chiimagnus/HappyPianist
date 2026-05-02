import RealityKit
import RealityKitContent
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
    private var handAnimationTask: Task<Void, Never>?
    private var leftArmPulseTask: Task<Void, Never>?
    private var rightArmPulseTask: Task<Void, Never>?
    private var latestSchedule: [PracticeSequencerMIDIEvent] = []
    private var wasPerforming = false
    private var nextNoteUsesLeftHand = true
    private var performerEntity: Entity?
    private var performerLoadTask: Task<Void, Never>?
    private var xiaochengRig: XiaochengRig?

    private struct XiaochengRig {
        let modelEntity: ModelEntity
        let restJointTransforms: [Transform]
        let leftArmJointIndices: [Int]
        let rightArmJointIndices: [Int]
    }

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
        performerLoadTask?.cancel()
        performerLoadTask = nil
        performerRootEntity?.removeFromParent()
        performerRootEntity = nil
        performerVisualRootEntity = nil
        performerPianoEntity = nil
        performerEntity = nil
        xiaochengRig = nil
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
        let performer = Entity()
        visualRoot.addChild(performer)
        performerEntity = performer
        loadXiaochengIfNeeded(into: performer)
        return root
    }

    private func loadXiaochengIfNeeded(into placeholder: Entity) {
        guard performerLoadTask == nil, xiaochengRig == nil else { return }

        performerLoadTask = Task { @MainActor [weak self, weak placeholder] in
            guard let self, let placeholder else { return }
            defer { self.performerLoadTask = nil }

            do {
                let entity = try await Entity(named: "xiaocheng", in: realityKitContentBundle)
                guard Task.isCancelled == false else { return }

                self.fitXiaochengToPlaceholder(entity: entity)

                guard let modelEntity = self.findFirstSkinnedModelEntity(in: entity),
                      let rig = self.makeXiaochengRig(modelEntity: modelEntity)
                else {
                    return
                }

                placeholder.children.removeAll(preservingWorldTransforms: false)
                placeholder.addChild(entity)
                self.xiaochengRig = rig
            } catch {
                // No fallback.
            }
        }
    }

    private func fitXiaochengToPlaceholder(entity: Entity) {
        let desiredHeightMeters: Float = 0.70

        let bounds = entity.visualBounds(recursive: true, relativeTo: entity)
        let currentHeight = max(0.001, bounds.extents.y)
        let scale = desiredHeightMeters / currentHeight
        entity.scale = SIMD3<Float>(repeating: scale)

        let scaledBounds = entity.visualBounds(recursive: true, relativeTo: entity)
        let minY = scaledBounds.center.y - scaledBounds.extents.y / 2
        entity.position.y -= minY
    }

    private func findFirstSkinnedModelEntity(in root: Entity) -> ModelEntity? {
        if let model = root as? ModelEntity, model.jointNames.isEmpty == false {
            return model
        }

        for child in root.children {
            if let found = findFirstSkinnedModelEntity(in: child) {
                return found
            }
        }
        return nil
    }

    private func makeXiaochengRig(modelEntity: ModelEntity) -> XiaochengRig? {
        let jointNames = modelEntity.jointNames
        guard jointNames.isEmpty == false else { return nil }

        func index(endsWith component: String) -> Int? {
            jointNames.firstIndex { $0 == component || $0.hasSuffix("/\(component)") }
        }

        let leftIndices = [index(endsWith: "LeftShoulder"), index(endsWith: "LeftArm"), index(endsWith: "LeftForeArm")].compactMap { $0 }
        let rightIndices = [index(endsWith: "RightShoulder"), index(endsWith: "RightArm"), index(endsWith: "RightForeArm")].compactMap { $0 }
        guard leftIndices.isEmpty == false || rightIndices.isEmpty == false else { return nil }

        var restTransforms = modelEntity.jointTransforms
        applyForwardRaisedArmsPose(jointNames: jointNames, jointTransforms: &restTransforms)
        modelEntity.jointTransforms = restTransforms

        return XiaochengRig(
            modelEntity: modelEntity,
            restJointTransforms: restTransforms,
            leftArmJointIndices: leftIndices,
            rightArmJointIndices: rightIndices
        )
    }

    private func applyForwardRaisedArmsPose(
        jointNames: [String],
        jointTransforms: inout [Transform]
    ) {
        func index(endsWith component: String) -> Int? {
            jointNames.firstIndex { $0 == component || $0.hasSuffix("/\(component)") }
        }

        func apply(arm: String, foreArm: String) {
            guard let armIndex = index(endsWith: arm),
                  let foreArmIndex = index(endsWith: foreArm),
                  armIndex < jointTransforms.count,
                  foreArmIndex < jointTransforms.count
            else {
                return
            }

            let foreArmTranslation = jointTransforms[foreArmIndex].translation
            let foreArmLength = simd_length(foreArmTranslation)
            guard foreArmLength > 0.0001 else { return }

            let localArmDirection = foreArmTranslation / foreArmLength
            let currentArmDirection = jointTransforms[armIndex].rotation.act(localArmDirection)

            let desiredArmDirection = simd_normalize(SIMD3<Float>(0, 0, -1))
            let delta = simd_quatf(from: currentArmDirection, to: desiredArmDirection)
            jointTransforms[armIndex].rotation = delta * jointTransforms[armIndex].rotation
        }

        apply(arm: "LeftArm", foreArm: "LeftForeArm")
        apply(arm: "RightArm", foreArm: "RightForeArm")
    }

    private func animateHead(isPerforming: Bool) {
        let nodEntity = performerEntity
        guard let nodEntity else { return }

        let baseTransform = nodEntity.transform
        var targetTransform = baseTransform
        targetTransform.rotation = simd_quatf(angle: isPerforming ? 0.6 : 0.0, axis: [1, 0, 0])
        _ = nodEntity.move(
            to: targetTransform,
            relativeTo: nodEntity.parent,
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
        guard let xiaochengRig else { return }
        animateXiaochengArmSwing(velocity: velocity, rig: xiaochengRig)
    }

    private func animateXiaochengArmSwing(velocity: UInt8, rig: XiaochengRig) {
        let isLeftArm = nextNoteUsesLeftHand
        nextNoteUsesLeftHand.toggle()

        let jointIndices = isLeftArm ? rig.leftArmJointIndices : rig.rightArmJointIndices
        guard jointIndices.isEmpty == false else { return }

        let normalizedVelocity = min(1, max(0, Float(velocity) / 127))
        let angleRadians: Float = -0.35 - normalizedVelocity * 0.5
        let deltaRotation = simd_quatf(angle: angleRadians, axis: [1, 0, 0])

        let task = Task { @MainActor in
            rig.modelEntity.jointTransforms = rig.restJointTransforms

            var transforms = rig.restJointTransforms
            for index in jointIndices where index < transforms.count {
                transforms[index].rotation = transforms[index].rotation * deltaRotation
            }
            rig.modelEntity.jointTransforms = transforms

            try? await Task.sleep(for: .milliseconds(90))
            rig.modelEntity.jointTransforms = rig.restJointTransforms
        }

        if isLeftArm {
            leftArmPulseTask?.cancel()
            leftArmPulseTask = task
        } else {
            rightArmPulseTask?.cancel()
            rightArmPulseTask = task
        }
    }

    private func resetArmsToRest(animated: Bool) {
        guard let xiaochengRig else { return }
        xiaochengRig.modelEntity.jointTransforms = xiaochengRig.restJointTransforms
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

    private func makePerformerPianoEntity(geometry: PianoKeyboardGeometry) -> Entity {
        let performerPianoScale: Float = 1.0

        let root = Entity()
        root.position = [0, 0.42, 0.34]
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
