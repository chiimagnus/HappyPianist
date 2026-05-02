import RealityKit
import RealityKitContent
import Dispatch
import simd
import SwiftUI
import UIKit
import os

@MainActor
final class VirtualPerformerOverlayController {
    private let logger = Logger(subsystem: "LonelyPianistAVP", category: "VirtualPerformer")
    private var rootEntity = Entity()
    private var hasAttachedRoot = false
    private var performerRootEntity: Entity?
    private var performerVisualRootEntity: Entity?
    private var performerPianoEntity: Entity?
    private var handAnimationTask: Task<Void, Never>?
    private var armMixerTask: Task<Void, Never>?
    private var headNodTask: Task<Void, Never>?
    private var leftArmPendingVelocities: [UInt8] = []
    private var rightArmPendingVelocities: [UInt8] = []
    private var leftArmPulses: [ArmPulse] = []
    private var rightArmPulses: [ArmPulse] = []
    private var latestSchedule: [PracticeSequencerMIDIEvent] = []
    private var wasPerforming = false
    private var performerEntity: Entity?
    private var performerLoadTask: Task<Void, Never>?
    private var xiaochengRig: XiaochengRig?
    private var xiaochengNodAngleRadians: Float = 0
    private var armSplitMidi: Int = 60
    private var usesAlternatingArms: Bool = false
    private var alternateNextIsLeftArm: Bool = true

    private struct ArmPulse {
        let startUptimeNanos: UInt64
        let amplitudeRadians: Float
    }

    private struct XiaochengRig {
        let modelEntity: ModelEntity
        let restJointTransforms: [Transform]
        let leftArmJointIndices: [Int]
        let rightArmJointIndices: [Int]
        let neckJointIndex: Int?
        let headJointIndex: Int?
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
        xiaochengNodAngleRadians = 0
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
        let desiredHeightMeters: Float = 0.3

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

        let neckIndex = index(endsWith: "Neck")
        let headIndex = index(endsWith: "Head")

        var restTransforms = modelEntity.jointTransforms
        applyForwardRaisedArmsPose(jointNames: jointNames, jointTransforms: &restTransforms)
        modelEntity.jointTransforms = restTransforms

        return XiaochengRig(
            modelEntity: modelEntity,
            restJointTransforms: restTransforms,
            leftArmJointIndices: leftIndices,
            rightArmJointIndices: rightIndices,
            neckJointIndex: neckIndex,
            headJointIndex: headIndex
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
        guard let xiaochengRig else { return }

        let targetAngleRadians: Float = isPerforming ? -0.35 : 0.0
        headNodTask?.cancel()
        headNodTask = Task { @MainActor [weak self] in
            guard let self else { return }

            let durationSeconds: Float = 0.25
            let steps: Int = 12
            let start = self.xiaochengNodAngleRadians
            for step in 1...steps {
                guard Task.isCancelled == false else { return }
                let t = Float(step) / Float(steps)
                let angle = start + (targetAngleRadians - start) * t
                self.xiaochengNodAngleRadians = angle
                self.applyXiaochengHeadNodPose(rig: xiaochengRig)
                let nanos = UInt64((durationSeconds / Float(steps)) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
            }
        }
    }

    private func applyXiaochengHeadNodPose(rig: XiaochengRig) {
        guard xiaochengNodAngleRadians != 0 else {
            rig.modelEntity.jointTransforms = makeXiaochengBaseTransforms(rig: rig)
            return
        }

        var transforms = rig.modelEntity.jointTransforms
        let rest = rig.restJointTransforms

        let headRotation = simd_quatf(angle: xiaochengNodAngleRadians, axis: [1, 0, 0])
        let neckRotation = simd_quatf(angle: xiaochengNodAngleRadians * 0.35, axis: [1, 0, 0])

        if let neckIndex = rig.neckJointIndex, neckIndex < transforms.count, neckIndex < rest.count {
            transforms[neckIndex].rotation = rest[neckIndex].rotation * neckRotation
        }
        if let headIndex = rig.headJointIndex, headIndex < transforms.count, headIndex < rest.count {
            transforms[headIndex].rotation = rest[headIndex].rotation * headRotation
        }

        rig.modelEntity.jointTransforms = transforms
    }

    private func applyHeadNodToBaseTransforms(
        angleRadians: Float,
        rig: XiaochengRig,
        jointTransforms: inout [Transform]
    ) {
        guard angleRadians != 0 else { return }

        let headRotation = simd_quatf(angle: angleRadians, axis: [1, 0, 0])
        if let neckIndex = rig.neckJointIndex, neckIndex < jointTransforms.count {
            jointTransforms[neckIndex].rotation = jointTransforms[neckIndex].rotation * simd_quatf(angle: angleRadians * 0.35, axis: [1, 0, 0])
        }
        if let headIndex = rig.headJointIndex, headIndex < jointTransforms.count {
            jointTransforms[headIndex].rotation = jointTransforms[headIndex].rotation * headRotation
        }
    }

    private func makeXiaochengBaseTransforms(rig: XiaochengRig) -> [Transform] {
        var transforms = rig.restJointTransforms
        applyHeadNodToBaseTransforms(angleRadians: xiaochengNodAngleRadians, rig: rig, jointTransforms: &transforms)
        return transforms
    }

    private func updateHandAnimationIfNeeded(schedule: [PracticeSequencerMIDIEvent]) {
        guard schedule != latestSchedule else { return }
        latestSchedule = schedule
        startHandAnimation(schedule: schedule)
    }

    private func startHandAnimation(schedule: [PracticeSequencerMIDIEvent]) {
        stopHandAnimation()
        resetArmsToRest(animated: false)

        let sortedSchedule = schedule.sorted { lhs, rhs in
            if lhs.timeSeconds != rhs.timeSeconds { return lhs.timeSeconds < rhs.timeSeconds }
            return eventPriority(lhs.kind) < eventPriority(rhs.kind)
        }

        let splitAndCounts = computeArmSplitMidiAndCounts(from: sortedSchedule)
        armSplitMidi = splitAndCounts?.splitMidi ?? 60
        usesAlternatingArms = (splitAndCounts?.isOneSided ?? false)
        alternateNextIsLeftArm = true

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
                    case let .noteOn(midi, velocity):
                        self.animateArmSwing(midi: midi, velocity: velocity)
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
        armMixerTask?.cancel()
        armMixerTask = nil
        leftArmPendingVelocities.removeAll(keepingCapacity: true)
        rightArmPendingVelocities.removeAll(keepingCapacity: true)
        leftArmPulses.removeAll(keepingCapacity: true)
        rightArmPulses.removeAll(keepingCapacity: true)
    }

    private func animateArmSwing(midi: Int, velocity: UInt8) {
        guard let xiaochengRig else { return }
        animateXiaochengArmSwing(midi: midi, velocity: velocity, rig: xiaochengRig)
    }

    private func animateXiaochengArmSwing(midi: Int, velocity: UInt8, rig: XiaochengRig) {
        let isLeftArm: Bool
        if usesAlternatingArms {
            isLeftArm = alternateNextIsLeftArm
            alternateNextIsLeftArm.toggle()
        } else {
            isLeftArm = midi < armSplitMidi
        }

        let hasArmJoints = isLeftArm ? (rig.leftArmJointIndices.isEmpty == false) : (rig.rightArmJointIndices.isEmpty == false)
        guard hasArmJoints else { return }

        if isLeftArm {
            leftArmPendingVelocities.append(velocity)
        } else {
            rightArmPendingVelocities.append(velocity)
        }

        startArmMixerIfNeeded(rig: rig)
    }

    private func computeArmSplitMidiAndCounts(from schedule: [PracticeSequencerMIDIEvent]) -> (splitMidi: Int, isOneSided: Bool)? {
        var noteOns: [Int] = []
        noteOns.reserveCapacity(64)
        for event in schedule {
            if case let .noteOn(midi, _) = event.kind {
                noteOns.append(midi)
            }
        }
        guard noteOns.isEmpty == false else { return nil }

        noteOns.sort()
        let medianMidi = noteOns[noteOns.count / 2]

        var leftCount = 0
        var rightCount = 0
        for midi in noteOns {
            if midi < medianMidi { leftCount += 1 } else { rightCount += 1 }
        }

        let isOneSided = leftCount == 0 || rightCount == 0
        if isOneSided {
            logger.info("Arm split median=\(medianMidi, privacy: .public) one-sided (L=\(leftCount, privacy: .public) R=\(rightCount, privacy: .public)); using alternating arms.")
        } else {
            logger.info("Arm split median=\(medianMidi, privacy: .public) (L=\(leftCount, privacy: .public) R=\(rightCount, privacy: .public)).")
        }
        return (medianMidi, isOneSided)
    }

    private func startArmMixerIfNeeded(rig: XiaochengRig) {
        guard armMixerTask == nil else { return }

        armMixerTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.armMixerTask = nil }

            let pulseDurationSeconds: Float = 0.14
            let tickMilliseconds: Int = 16

            while Task.isCancelled == false {
                let nowNanos = DispatchTime.now().uptimeNanoseconds

                self.drainPendingVelocitiesIntoPulses(nowNanos: nowNanos)

                let hasPendingWork = self.leftArmPendingVelocities.isEmpty == false
                    || self.rightArmPendingVelocities.isEmpty == false
                    || self.leftArmPulses.isEmpty == false
                    || self.rightArmPulses.isEmpty == false
                if hasPendingWork == false {
                    rig.modelEntity.jointTransforms = self.makeXiaochengBaseTransforms(rig: rig)
                    return
                }

                let leftAngle = self.summedAngleRadians(
                    pulses: &self.leftArmPulses,
                    nowUptimeNanos: nowNanos,
                    pulseDurationSeconds: pulseDurationSeconds
                )
                let rightAngle = self.summedAngleRadians(
                    pulses: &self.rightArmPulses,
                    nowUptimeNanos: nowNanos,
                    pulseDurationSeconds: pulseDurationSeconds
                )

                var transforms = self.makeXiaochengBaseTransforms(rig: rig)
                if leftAngle != 0, rig.leftArmJointIndices.isEmpty == false {
                    let delta = simd_quatf(angle: leftAngle, axis: [1, 0, 0])
                    for index in rig.leftArmJointIndices where index < transforms.count {
                        transforms[index].rotation = transforms[index].rotation * delta
                    }
                }
                if rightAngle != 0, rig.rightArmJointIndices.isEmpty == false {
                    let delta = simd_quatf(angle: -rightAngle, axis: [-1, 0, 0])
                    for index in rig.rightArmJointIndices where index < transforms.count {
                        transforms[index].rotation = transforms[index].rotation * delta
                    }
                }
                rig.modelEntity.jointTransforms = transforms

                try? await Task.sleep(for: .milliseconds(tickMilliseconds))
            }
        }
    }

    private func drainPendingVelocitiesIntoPulses(nowNanos: UInt64) {
        while leftArmPendingVelocities.isEmpty == false {
            let velocity = leftArmPendingVelocities.removeFirst()
            leftArmPulses.append(makePulse(startUptimeNanos: nowNanos, velocity: velocity))
        }
        while rightArmPendingVelocities.isEmpty == false {
            let velocity = rightArmPendingVelocities.removeFirst()
            rightArmPulses.append(makePulse(startUptimeNanos: nowNanos, velocity: velocity))
        }
    }

    private func makePulse(startUptimeNanos: UInt64, velocity: UInt8) -> ArmPulse {
        let normalizedVelocity = min(1, max(0, Float(velocity) / 127))
        let peakAngleRadians: Float = -0.35 - normalizedVelocity * 0.5
        return ArmPulse(startUptimeNanos: startUptimeNanos, amplitudeRadians: peakAngleRadians)
    }

    private func summedAngleRadians(
        pulses: inout [ArmPulse],
        nowUptimeNanos: UInt64,
        pulseDurationSeconds: Float
    ) -> Float {
        guard pulseDurationSeconds > 0 else { return 0 }

        var total: Float = 0
        var next: [ArmPulse] = []
        next.reserveCapacity(pulses.count)

        for pulse in pulses {
            let dtSeconds = Float(Double(nowUptimeNanos &- pulse.startUptimeNanos) / 1_000_000_000.0)
            if dtSeconds < 0 {
                next.append(pulse)
                continue
            }
            if dtSeconds >= pulseDurationSeconds {
                continue
            }

            let t = dtSeconds / pulseDurationSeconds
            let env = triangularEaseInOut(t)
            total += pulse.amplitudeRadians * env
            next.append(pulse)
        }

        pulses = next
        return total
    }

    private func triangularEaseInOut(_ t: Float) -> Float {
        if t <= 0 { return 0 }
        if t >= 1 { return 0 }

        let x = t < 0.5 ? (t * 2) : ((1 - t) * 2)
        return smoothstep(x)
    }

    private func smoothstep(_ x: Float) -> Float {
        let clamped = min(1, max(0, x))
        return clamped * clamped * (3 - 2 * clamped)
    }

    private func resetArmsToRest(animated: Bool) {
        guard let xiaochengRig else { return }
        xiaochengRig.modelEntity.jointTransforms = makeXiaochengBaseTransforms(rig: xiaochengRig)
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
        root.position = [0, 0.35, 0.15]
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
