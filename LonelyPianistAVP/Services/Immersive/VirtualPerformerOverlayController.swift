import Foundation
import os
import RealityKit
import RealityKitContent
import simd
import SwiftUI
import UIKit

@MainActor
final class VirtualPerformerOverlayController {
    private let logger = Logger(subsystem: "LonelyPianistAVP", category: "VirtualPerformer")
    private let debugLogger = Logger(subsystem: "LonelyPianistAVP", category: "VirtualPerformerDebug")
    private var rootEntity = Entity()
    private var hasAttachedRoot = false
    private var performerRootEntity: Entity?
    private var performerLateralRootEntity: Entity?
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
    private var latestActiveMIDINote: Int?
    private var currentLateralOffsetMeters: Float = 0
    private var currentLateralSpeedMetersPerSecond: Float = 0
    private var lastLateralUpdateUptime: TimeInterval?
    private var gaitPhaseRadians: Float = 0
    private var lastDebugLogUptime: TimeInterval?
    private var didLogMissingLegJoints = false

    private let lateralMotionResolver: any VirtualPerformerLateralMotionResolving = DefaultVirtualPerformerLateralMotionResolver()
    private let gaitResolver: any VirtualPerformerGaitResolving = DefaultVirtualPerformerGaitResolver()

    private struct ArmPulse {
        let startUptimeNanos: UInt64
        let amplitudeRadians: Float
    }

    protocol VirtualPerformerLateralMotionResolving {
        func desiredLateralOffsetMeters(
            keyboardGeometry: PianoKeyboardGeometry,
            activeMIDINote: Int?
        ) -> Float
    }

    struct DefaultVirtualPerformerLateralMotionResolver: VirtualPerformerLateralMotionResolving {
        func desiredLateralOffsetMeters(
            keyboardGeometry: PianoKeyboardGeometry,
            activeMIDINote: Int?
        ) -> Float {
            guard let activeMIDINote, let key = keyboardGeometry.key(for: activeMIDINote) else { return 0 }

            // Map the active key center's X into a centered offset (A0..C8 => roughly -L/2..+L/2).
            let xs = keyboardGeometry.keys.map(\.localCenter.x)
            guard let minX = xs.min(), let maxX = xs.max(), maxX > minX else { return 0 }
            let centerX = (minX + maxX) / 2
            let raw = key.localCenter.x - centerX

            // Don't let the performer travel the full keyboard range; keep it subtle.
            let maxTravel = (maxX - minX) * 0.32
            return min(maxTravel, max(-maxTravel, raw))
        }
    }

    struct VirtualPerformerGaitPose: Equatable {
        let leftAngleRadians: Float
        let rightAngleRadians: Float
    }

    protocol VirtualPerformerGaitResolving {
        func gaitPose(
            phaseRadians: Float,
            lateralSpeedMetersPerSecond: Float
        ) -> VirtualPerformerGaitPose
    }

    struct DefaultVirtualPerformerGaitResolver: VirtualPerformerGaitResolving {
        func gaitPose(
            phaseRadians: Float,
            lateralSpeedMetersPerSecond: Float
        ) -> VirtualPerformerGaitPose {
            let speed = abs(lateralSpeedMetersPerSecond)
            guard speed > 0.02 else {
                return VirtualPerformerGaitPose(leftAngleRadians: 0, rightAngleRadians: 0)
            }

            // Conservative "walk-in-place" swing. Direction doesn't matter for the visual.
            let amplitude: Float = min(0.45, 0.12 + speed * 0.25)
            let s = sin(phaseRadians)
            return VirtualPerformerGaitPose(
                leftAngleRadians: amplitude * s,
                rightAngleRadians: amplitude * -s
            )
        }
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

        logDebugStatusIfNeeded(
            isEnabled: isEnabled,
            isPerforming: isPerforming,
            keyboardGeometry: keyboardGeometry,
            performanceSchedule: performanceSchedule
        )

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

    private func showPerformer(geometry: PianoKeyboardGeometry, cameraWorldPosition _: SIMD3<Float>?) {
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

        if let performerLateralRootEntity {
            applyLateralOffsetIfNeeded(
                keyboardGeometry: geometry,
                lateralRootEntity: performerLateralRootEntity
            )
        }

        if let xiaochengRig, shouldAnimateGait() {
            startArmMixerIfNeeded(rig: xiaochengRig)
        }

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
        performerLateralRootEntity = nil
        performerVisualRootEntity = nil
        performerPianoEntity = nil
        performerEntity = nil
        xiaochengRig = nil
        xiaochengNodAngleRadians = 0
        latestSchedule = []
        wasPerforming = false
        latestActiveMIDINote = nil
        currentLateralOffsetMeters = 0
        currentLateralSpeedMetersPerSecond = 0
        lastLateralUpdateUptime = nil
        gaitPhaseRadians = 0
        lastDebugLogUptime = nil
        didLogMissingLegJoints = false
    }

    private func makePerformerRootEntity(geometry: PianoKeyboardGeometry) -> Entity {
        let root = Entity()
        let lateralRoot = Entity()
        root.addChild(lateralRoot)
        performerLateralRootEntity = lateralRoot
        let visualRoot = Entity()
        lateralRoot.addChild(visualRoot)
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

    private func applyLateralOffsetIfNeeded(
        keyboardGeometry: PianoKeyboardGeometry,
        lateralRootEntity: Entity
    ) {
        let desired = lateralMotionResolver.desiredLateralOffsetMeters(
            keyboardGeometry: keyboardGeometry,
            activeMIDINote: latestActiveMIDINote
        )

        let now = ProcessInfo.processInfo.systemUptime
        let dt = lastLateralUpdateUptime.map { max(0, now - $0) } ?? 0
        lastLateralUpdateUptime = now

        // Exponential-ish smoothing with a short time constant for perceptible, non-jittery motion.
        let timeConstant: TimeInterval = 0.22
        let alpha = dt > 0 ? min(1, dt / timeConstant) : 1
        let previous = currentLateralOffsetMeters
        currentLateralOffsetMeters = currentLateralOffsetMeters
            + (desired - currentLateralOffsetMeters) * Float(alpha)

        lateralRootEntity.position.x = currentLateralOffsetMeters

        if dt > 0 {
            currentLateralSpeedMetersPerSecond = (currentLateralOffsetMeters - previous) / Float(dt)
            advanceGaitPhase(dtSeconds: dt)
        } else {
            currentLateralSpeedMetersPerSecond = 0
        }
    }

    private func advanceGaitPhase(dtSeconds: TimeInterval) {
        let speed = abs(currentLateralSpeedMetersPerSecond)
        let baseHz: Float = 1.2
        let extraHz: Float = min(2.8, speed * 3.0)
        let hz = baseHz + extraHz
        gaitPhaseRadians += 2 * .pi * hz * Float(dtSeconds)
        if gaitPhaseRadians > 10000 { gaitPhaseRadians.formTruncatingRemainder(dividingBy: 2 * .pi) }
    }

    private func shouldAnimateGait() -> Bool {
        abs(currentLateralSpeedMetersPerSecond) > 0.02
    }

    private func logDebugStatusIfNeeded(
        isEnabled: Bool,
        isPerforming: Bool,
        keyboardGeometry: PianoKeyboardGeometry,
        performanceSchedule: [PracticeSequencerMIDIEvent]
    ) {
        let now = ProcessInfo.processInfo.systemUptime
        let interval: TimeInterval = 1.0
        if let last = lastDebugLogUptime, now - last < interval {
            return
        }
        lastDebugLogUptime = now

        let scheduleNoteOnCount = performanceSchedule.reduce(into: 0) { partialResult, event in
            if case .noteOn = event.kind { partialResult += 1 }
        }
        let scheduleSeconds: (min: TimeInterval, max: TimeInterval)? = {
            guard performanceSchedule.isEmpty == false else { return nil }
            let times = performanceSchedule.map(\.timeSeconds)
            guard let min = times.min(), let max = times.max() else { return nil }
            return (min, max)
        }()

        let rigSummary: String = if let xiaochengRig {
            "rig=Y arms(L=\(xiaochengRig.leftArmJointIndices.count) R=\(xiaochengRig.rightArmJointIndices.count)) legs(L=\(xiaochengRig.leftLegJointIndices.count) R=\(xiaochengRig.rightLegJointIndices.count))"
        } else {
            "rig=N"
        }

        let scheduleSummary: String = if let scheduleSeconds {
            "schedule=\(performanceSchedule.count) noteOn=\(scheduleNoteOnCount) t=[\(scheduleSeconds.min),\(scheduleSeconds.max)]"
        } else {
            "schedule=0"
        }

        debugLogger.info(
            "update enabled=\(isEnabled, privacy: .public) performing=\(isPerforming, privacy: .public) keys=\(keyboardGeometry.keys.count, privacy: .public) \(scheduleSummary, privacy: .public) activeMidi=\(String(describing: self.latestActiveMIDINote), privacy: .public) x=\(self.currentLateralOffsetMeters, privacy: .public) vx=\(self.currentLateralSpeedMetersPerSecond, privacy: .public) \(rigSummary, privacy: .public)"
        )
    }

    private func loadXiaochengIfNeeded(into placeholder: Entity) {
        guard performerLoadTask == nil, xiaochengRig == nil else { return }

        performerLoadTask = Task { @MainActor [weak self, weak placeholder] in
            guard let self, let placeholder else { return }
            defer { self.performerLoadTask = nil }

            do {
                let entity = try await Entity(named: "xiaocheng", in: realityKitContentBundle)
                guard Task.isCancelled == false else { return }

                fitXiaochengToPlaceholder(entity: entity)

                guard let modelEntity = findFirstSkinnedModelEntity(in: entity),
                      let rig = XiaochengRigBuilder.makeRig(modelEntity: modelEntity)
                else {
                    return
                }

                placeholder.children.removeAll(preservingWorldTransforms: false)
                placeholder.addChild(entity)
                xiaochengRig = rig

                debugLogger.info(
                    "xiaocheng loaded arms(L=\(rig.leftArmJointIndices.count, privacy: .public) R=\(rig.rightArmJointIndices.count, privacy: .public)) legs(L=\(rig.leftLegJointIndices.count, privacy: .public) R=\(rig.rightLegJointIndices.count, privacy: .public)) neck=\(rig.neckJointIndex != nil, privacy: .public) head=\(rig.headJointIndex != nil, privacy: .public)"
                )
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

    private func animateHead(isPerforming: Bool) {
        guard let xiaochengRig else { return }

        let targetAngleRadians: Float = isPerforming ? -0.35 : 0.0
        headNodTask?.cancel()
        headNodTask = Task { @MainActor [weak self] in
            guard let self else { return }

            let durationSeconds: Float = 0.25
            let steps = 12
            let start = xiaochengNodAngleRadians
            for step in 1 ... steps {
                guard Task.isCancelled == false else { return }
                let t = Float(step) / Float(steps)
                let angle = start + (targetAngleRadians - start) * t
                xiaochengNodAngleRadians = angle
                XiaochengPoseService.applyHeadNodPose(rig: xiaochengRig, headNodAngleRadians: angle)
                let stepSeconds = Double(durationSeconds / Float(steps))
                try? await Task.sleep(for: .seconds(stepSeconds))
            }
        }
    }

    private func updateHandAnimationIfNeeded(schedule: [PracticeSequencerMIDIEvent]) {
        guard schedule != latestSchedule else { return }
        if schedule.isEmpty {
            debugLogger.info("schedule updated: empty")
        } else {
            let noteOnCount = schedule.reduce(into: 0) { partialResult, event in
                if case .noteOn = event.kind { partialResult += 1 }
            }
            let minT = schedule.map(\.timeSeconds).min() ?? 0
            let maxT = schedule.map(\.timeSeconds).max() ?? 0
            debugLogger.info(
                "schedule updated: count=\(schedule.count, privacy: .public) noteOn=\(noteOnCount, privacy: .public) t=[\(minT, privacy: .public),\(maxT, privacy: .public)]"
            )
        }
        latestSchedule = schedule
        startHandAnimation(schedule: schedule)
    }

    private func startHandAnimation(schedule: [PracticeSequencerMIDIEvent]) {
        stopHandAnimation()
        resetArmsToRest(animated: false)
        latestActiveMIDINote = nil

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
            var index = 0
            let groupEpsilon: TimeInterval = 0.0005

            while index < sortedSchedule.count {
                guard Task.isCancelled == false else { return }
                let groupTime = sortedSchedule[index].timeSeconds
                let delaySeconds = max(0, groupTime - previousTimeSeconds)
                if delaySeconds > 0 {
                    try? await Task.sleep(for: .seconds(delaySeconds))
                }
                guard Task.isCancelled == false else { return }

                var noteOns: [(midi: Int, velocity: UInt8)] = []
                while index < sortedSchedule.count {
                    let event = sortedSchedule[index]
                    if abs(event.timeSeconds - groupTime) > groupEpsilon { break }
                    if case let .noteOn(midi, velocity) = event.kind {
                        noteOns.append((midi: midi, velocity: velocity))
                    }
                    index += 1
                }

                if noteOns.isEmpty == false {
                    let target = resolvedTargetMIDINote(noteOns: noteOns)
                    latestActiveMIDINote = target

                    for item in noteOns {
                        animateArmSwing(midi: item.midi, velocity: item.velocity)
                    }
                }

                previousTimeSeconds = groupTime
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
        latestActiveMIDINote = nil
    }

    private func resolvedTargetMIDINote(noteOns: [(midi: Int, velocity: UInt8)]) -> Int {
        let midis = noteOns.map(\.midi).sorted()
        return midis[midis.count / 2]
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

        let hasArmJoints = isLeftArm ? (rig.leftArmJointIndices.isEmpty == false) :
            (rig.rightArmJointIndices.isEmpty == false)
        guard hasArmJoints else { return }

        if isLeftArm {
            leftArmPendingVelocities.append(velocity)
        } else {
            rightArmPendingVelocities.append(velocity)
        }

        startArmMixerIfNeeded(rig: rig)
    }

    private func computeArmSplitMidiAndCounts(from schedule: [PracticeSequencerMIDIEvent])
        -> (splitMidi: Int, isOneSided: Bool)?
    {
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
            logger
                .info(
                    "Arm split median=\(medianMidi, privacy: .public) one-sided (L=\(leftCount, privacy: .public) R=\(rightCount, privacy: .public)); using alternating arms."
                )
        } else {
            logger
                .info(
                    "Arm split median=\(medianMidi, privacy: .public) (L=\(leftCount, privacy: .public) R=\(rightCount, privacy: .public))."
                )
        }
        return (medianMidi, isOneSided)
    }

    private func startArmMixerIfNeeded(rig: XiaochengRig) {
        guard armMixerTask == nil else { return }

        if didLogMissingLegJoints == false {
            didLogMissingLegJoints = true
            if rig.leftLegJointIndices.isEmpty && rig.rightLegJointIndices.isEmpty {
                debugLogger.info("gait: leg joints not found in rig; leg animation will be skipped")
            }
        }

        armMixerTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.armMixerTask = nil }

            let pulseDurationSeconds: Float = 0.14
            let tickMilliseconds = 16

            while Task.isCancelled == false {
                let nowNanos = DispatchTime.now().uptimeNanoseconds

                drainPendingVelocitiesIntoPulses(nowNanos: nowNanos)

                let gaitPose = gaitResolver.gaitPose(
                    phaseRadians: gaitPhaseRadians,
                    lateralSpeedMetersPerSecond: currentLateralSpeedMetersPerSecond
                )

                let hasPendingWork = leftArmPendingVelocities.isEmpty == false
                    || rightArmPendingVelocities.isEmpty == false
                    || leftArmPulses.isEmpty == false
                    || rightArmPulses.isEmpty == false
                    || gaitPose.leftAngleRadians != 0
                    || gaitPose.rightAngleRadians != 0
                if hasPendingWork == false {
                    rig.modelEntity.jointTransforms = XiaochengPoseService.baseTransforms(
                        rig: rig,
                        headNodAngleRadians: xiaochengNodAngleRadians
                    )
                    return
                }

                let leftAngle = summedAngleRadians(
                    pulses: &leftArmPulses,
                    nowUptimeNanos: nowNanos,
                    pulseDurationSeconds: pulseDurationSeconds
                )
                let rightAngle = summedAngleRadians(
                    pulses: &rightArmPulses,
                    nowUptimeNanos: nowNanos,
                    pulseDurationSeconds: pulseDurationSeconds
                )

                var transforms = XiaochengPoseService.baseTransforms(
                    rig: rig,
                    headNodAngleRadians: xiaochengNodAngleRadians
                )
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

                applyGaitPose(
                    gaitPose,
                    transforms: &transforms,
                    rig: rig
                )
                rig.modelEntity.jointTransforms = transforms

                try? await Task.sleep(for: .milliseconds(tickMilliseconds))
            }
        }
    }

    private func applyGaitPose(
        _ pose: VirtualPerformerGaitPose,
        transforms: inout [Transform],
        rig: XiaochengRig
    ) {
        guard pose.leftAngleRadians != 0 || pose.rightAngleRadians != 0 else { return }

        applyLegSwing(
            swingAngleRadians: pose.leftAngleRadians,
            jointIndices: rig.leftLegJointIndices,
            transforms: &transforms
        )
        applyLegSwing(
            swingAngleRadians: pose.rightAngleRadians,
            jointIndices: rig.rightLegJointIndices,
            transforms: &transforms
        )
    }

    private func applyLegSwing(
        swingAngleRadians: Float,
        jointIndices: [Int],
        transforms: inout [Transform]
    ) {
        guard swingAngleRadians != 0 else { return }
        guard jointIndices.isEmpty == false else { return }

        // The exact joint axes depend on the asset. We intentionally keep the motion small and simple:
        // a forward/back thigh swing + a slightly counter-rotated lower leg to mimic stepping.
        let thighDelta = simd_quatf(angle: swingAngleRadians, axis: [1, 0, 0])
        let calfDelta = simd_quatf(angle: -swingAngleRadians * 0.55, axis: [1, 0, 0])
        let footDelta = simd_quatf(angle: swingAngleRadians * 0.15, axis: [1, 0, 0])

        for (slot, index) in jointIndices.enumerated() where index < transforms.count {
            switch slot {
            case 0:
                transforms[index].rotation = transforms[index].rotation * thighDelta
            case 1:
                transforms[index].rotation = transforms[index].rotation * calfDelta
            default:
                transforms[index].rotation = transforms[index].rotation * footDelta
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

    private func resetArmsToRest(animated _: Bool) {
        guard let xiaochengRig else { return }
        xiaochengRig.modelEntity.jointTransforms = XiaochengPoseService.baseTransforms(
            rig: xiaochengRig,
            headNodAngleRadians: xiaochengNodAngleRadians
        )
    }

    private func eventPriority(_ kind: PracticeSequencerMIDIEvent.Kind) -> Int {
        switch kind {
        case .controlChange:
            0
        case .programChange, .pitchBend, .channelPressure, .polyPressure:
            1
        case .noteOff:
            2
        case .noteOn:
            3
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
