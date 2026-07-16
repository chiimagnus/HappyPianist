import Foundation
import RealityKit
import RealityKitContent
import simd
import SwiftUI
import UIKit

@MainActor
final class VirtualPerformerOverlayController {
    private let keyEntityFactory: PianoKeyEntityFactory
    private let diagnosticsReporter: (any DiagnosticsReporting)?
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
    private var lateralScheduleStartUptime: TimeInterval?
    private var lateralTargetTimeline: [(timeSeconds: TimeInterval, midi: Int)] = []
    private var latestLateralTargetMIDINote: Int?
    private var currentLateralOffsetMeters: Float = 0
    private var currentLateralSpeedMetersPerSecond: Float = 0
    private var lastLateralUpdateUptime: TimeInterval?
    private var gaitPhaseRadians: Float = 0
    private var cachedKeyboardLayoutID: UUID?
    private var cachedKeyboardLayout: VirtualPerformerKeyboardLayout?

    private let lateralMotionResolver: any VirtualPerformerLateralMotionResolving = DefaultVirtualPerformerLateralMotionResolver()
    private let gaitResolver: any VirtualPerformerGaitResolving = DefaultVirtualPerformerGaitResolver()
    private var reduceMotionEnabled = false

    init(
        keyEntityFactory: PianoKeyEntityFactory = PianoKeyEntityFactory(),
        diagnosticsReporter: (any DiagnosticsReporting)? = nil
    ) {
        self.keyEntityFactory = keyEntityFactory
        self.diagnosticsReporter = diagnosticsReporter
    }

    var hasActiveRuntimeResources: Bool {
        performerRootEntity != nil
            || performerLateralRootEntity != nil
            || performerVisualRootEntity != nil
            || performerPianoEntity != nil
            || performerEntity != nil
            || xiaochengRig != nil
            || handAnimationTask != nil
            || armMixerTask != nil
            || headNodTask != nil
            || performerLoadTask != nil
    }

    private struct ArmPulse {
        let startUptimeNanos: UInt64
        let amplitudeRadians: Float
    }

    struct VirtualPerformerKeyboardLayout: Equatable {
        let centerXByMIDINote: [Int: Float]
        let minX: Float
        let maxX: Float

        init?(keyboardGeometry: PianoKeyboardGeometry) {
            guard let firstKey = keyboardGeometry.keys.first else { return nil }

            var centers: [Int: Float] = [:]
            centers.reserveCapacity(keyboardGeometry.keys.count)
            var minX = firstKey.localCenter.x
            var maxX = firstKey.localCenter.x
            for key in keyboardGeometry.keys {
                let x = key.localCenter.x
                centers[key.midiNote] = x
                minX = min(minX, x)
                maxX = max(maxX, x)
            }
            guard maxX > minX else { return nil }

            centerXByMIDINote = centers
            self.minX = minX
            self.maxX = maxX
        }
    }

    protocol VirtualPerformerLateralMotionResolving {
        func desiredLateralOffsetMeters(
            keyboardLayout: VirtualPerformerKeyboardLayout,
            activeMIDINote: Int?
        ) -> Float
    }

    struct DefaultVirtualPerformerLateralMotionResolver: VirtualPerformerLateralMotionResolving {
        func desiredLateralOffsetMeters(
            keyboardLayout: VirtualPerformerKeyboardLayout,
            activeMIDINote: Int?
        ) -> Float {
            guard let activeMIDINote,
                  let keyCenterX = keyboardLayout.centerXByMIDINote[activeMIDINote]
            else { return 0 }

            let centerX = (keyboardLayout.minX + keyboardLayout.maxX) / 2
            let raw = keyCenterX - centerX
            let maxTravel = (keyboardLayout.maxX - keyboardLayout.minX) * 0.32
            let clamped = min(maxTravel, max(-maxTravel, raw))

            let minVisibleTravelMeters: Float = 0.06
            if abs(clamped) < minVisibleTravelMeters {
                return clamped == 0 ? 0 : minVisibleTravelMeters * (clamped > 0 ? 1 : -1)
            }
            return clamped
        }

        func desiredLateralOffsetMeters(
            keyboardGeometry: PianoKeyboardGeometry,
            activeMIDINote: Int?
        ) -> Float {
            guard let keyboardLayout = VirtualPerformerKeyboardLayout(keyboardGeometry: keyboardGeometry) else {
                return 0
            }
            return desiredLateralOffsetMeters(
                keyboardLayout: keyboardLayout,
                activeMIDINote: activeMIDINote
            )
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
        reduceMotion: Bool,
        performanceSchedule: [PracticeSequencerMIDIEvent] = [],
        content: RealityViewContent?
    ) {
        let didEnableReduceMotion = reduceMotion && reduceMotionEnabled == false
        reduceMotionEnabled = reduceMotion
        if hasAttachedRoot == false, let content {
            content.add(rootEntity)
            hasAttachedRoot = true
        }

        guard isEnabled, let keyboardGeometry else {
            clearPerformer()
            return
        }

        showPerformer(geometry: keyboardGeometry)

        if didEnableReduceMotion {
            headNodTask?.cancel()
            headNodTask = nil
            xiaochengNodAngleRadians = 0
            stopHandAnimation()
            latestSchedule = []
            resetArmsToRest(animated: false)
        }

        if wasPerforming != isPerforming {
            if reduceMotion {
                headNodTask?.cancel()
                headNodTask = nil
                xiaochengNodAngleRadians = 0
                resetArmsToRest(animated: false)
            } else {
                animateHead(isPerforming: isPerforming)
            }
            wasPerforming = isPerforming
        }

        // Drive hand/pose animation from the schedule itself, not from `isPerforming`.
        // Reduce Motion keeps the performer static instead of merely shortening the animation.
        if reduceMotion {
            stopHandAnimation()
            latestSchedule = []
        } else {
            updateHandAnimationIfNeeded(schedule: performanceSchedule)
        }
    }

    private func showPerformer(geometry: PianoKeyboardGeometry) {
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

        if let xiaochengRig, reduceMotionEnabled == false, shouldAnimateGait() {
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

    func reset() {
        clearPerformer()
        rootEntity.removeFromParent()
        hasAttachedRoot = false
    }

    private func clearPerformer() {
        stopHandAnimation()
        headNodTask?.cancel()
        headNodTask = nil
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
        lateralScheduleStartUptime = nil
        lateralTargetTimeline.removeAll(keepingCapacity: true)
        latestLateralTargetMIDINote = nil
        currentLateralOffsetMeters = 0
        currentLateralSpeedMetersPerSecond = 0
        lastLateralUpdateUptime = nil
        gaitPhaseRadians = 0
        cachedKeyboardLayoutID = nil
        cachedKeyboardLayout = nil
    }

    private func makePerformerRootEntity(geometry: PianoKeyboardGeometry) -> Entity {
        let root = Entity()
        let visualRoot = Entity()
        root.addChild(visualRoot)
        performerVisualRootEntity = visualRoot
        let piano = makePerformerPianoEntity(geometry: geometry)
        visualRoot.addChild(piano)
        performerPianoEntity = piano
        let lateralRoot = Entity()
        visualRoot.addChild(lateralRoot)
        performerLateralRootEntity = lateralRoot
        let performer = Entity()
        lateralRoot.addChild(performer)
        performerEntity = performer
        loadXiaochengIfNeeded(into: performer)
        return root
    }

    private func applyLateralOffsetIfNeeded(
        keyboardGeometry: PianoKeyboardGeometry,
        lateralRootEntity: Entity
    ) {
        // Resolve a time-based "active note" from the schedule, so lateral motion stays real-time even
        // if arm/rig animation tasks are delayed on the MainActor (common in Simulator).
        let nowUptime = ProcessInfo.processInfo.systemUptime
        latestLateralTargetMIDINote = resolveLateralTargetMIDINote(nowUptimeSeconds: nowUptime)

        let desired: Float = if reduceMotionEnabled {
            0
        } else if let keyboardLayout = keyboardLayout(for: keyboardGeometry) {
            lateralMotionResolver.desiredLateralOffsetMeters(
                keyboardLayout: keyboardLayout,
                activeMIDINote: latestLateralTargetMIDINote
            )
        } else {
            0
        }

        let dt = lastLateralUpdateUptime.map { max(0, nowUptime - $0) } ?? 0
        lastLateralUpdateUptime = nowUptime

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

    private func keyboardLayout(for geometry: PianoKeyboardGeometry) -> VirtualPerformerKeyboardLayout? {
        if geometry.cacheID != cachedKeyboardLayoutID {
            cachedKeyboardLayoutID = geometry.cacheID
            cachedKeyboardLayout = VirtualPerformerKeyboardLayout(keyboardGeometry: geometry)
        }
        return cachedKeyboardLayout
    }

    private func rebuildLateralTargetTimeline(schedule: [PracticeSequencerMIDIEvent]) {
        lateralTargetTimeline.removeAll(keepingCapacity: true)
        guard schedule.isEmpty == false else { return }

        let sorted = schedule.sorted { $0.timeSeconds < $1.timeSeconds }
        let groupEpsilon: TimeInterval = 0.0005

        var index = 0
        while index < sorted.count {
            let groupTime = sorted[index].timeSeconds
            var noteOns: [Int] = []
            while index < sorted.count {
                let event = sorted[index]
                if abs(event.timeSeconds - groupTime) > groupEpsilon { break }
                if case let .noteOn(midi, _) = event.kind {
                    noteOns.append(midi)
                }
                index += 1
            }
            guard noteOns.isEmpty == false else { continue }
            noteOns.sort()
            let median = noteOns[noteOns.count / 2]
            lateralTargetTimeline.append((timeSeconds: groupTime, midi: median))
        }
    }

    private func resolveLateralTargetMIDINote(nowUptimeSeconds: TimeInterval) -> Int? {
        guard let start = lateralScheduleStartUptime else { return nil }
        guard lateralTargetTimeline.isEmpty == false else { return nil }

        let elapsed = max(0, nowUptimeSeconds - start)

        // After the phrase ends, recentre after a short tail so the performer doesn't get stuck.
        if let last = lateralTargetTimeline.last, elapsed > last.timeSeconds + 0.45 {
            return nil
        }

        // Pick the most recent target at or before "now".
        // Linear scan is fine for these small schedules; keep it simple.
        var candidate: Int?
        for item in lateralTargetTimeline {
            if item.timeSeconds <= elapsed {
                candidate = item.midi
            } else {
                break
            }
        }
        return candidate
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
            } catch {
                diagnosticsReporter?.recordSystem(
                    severity: .error,
                    category: .immersiveSpace,
                    stage: "virtualPerformer.loadAsset",
                    summary: "虚拟演奏者资源加载失败",
                    reason: String(describing: error)
                )
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
        latestSchedule = schedule
        lateralScheduleStartUptime = schedule.isEmpty ? nil : ProcessInfo.processInfo.systemUptime
        rebuildLateralTargetTimeline(schedule: schedule)
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

        return (medianMidi, leftCount == 0 || rightCount == 0)
    }

    private func startArmMixerIfNeeded(rig: XiaochengRig) {
        guard armMixerTask == nil else { return }

        armMixerTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.armMixerTask = nil }

            let pulseDurationSeconds: Float = 0.14
            let tickMilliseconds = 33
            let animatedJointIndices = Set(
                rig.leftArmJointIndices
                    + rig.rightArmJointIndices
                    + rig.leftLegJointIndices
                    + rig.rightLegJointIndices
            )
            var cachedHeadNodAngle = xiaochengNodAngleRadians
            var baseTransforms = XiaochengPoseService.baseTransforms(
                rig: rig,
                headNodAngleRadians: cachedHeadNodAngle
            )
            var transforms = baseTransforms

            while Task.isCancelled == false {
                let nowNanos = UInt64(ProcessInfo.processInfo.systemUptime * 1_000_000_000)
                drainPendingVelocitiesIntoPulses(nowNanos: nowNanos)

                let gaitPose = gaitResolver.gaitPose(
                    phaseRadians: gaitPhaseRadians,
                    lateralSpeedMetersPerSecond: currentLateralSpeedMetersPerSecond
                )
                let hasPendingWork = leftArmPulses.isEmpty == false
                    || rightArmPulses.isEmpty == false
                    || gaitPose.leftAngleRadians != 0
                    || gaitPose.rightAngleRadians != 0

                if cachedHeadNodAngle != xiaochengNodAngleRadians {
                    cachedHeadNodAngle = xiaochengNodAngleRadians
                    baseTransforms = XiaochengPoseService.baseTransforms(
                        rig: rig,
                        headNodAngleRadians: cachedHeadNodAngle
                    )
                    transforms = baseTransforms
                } else {
                    for index in animatedJointIndices where index < transforms.count && index < baseTransforms.count {
                        transforms[index] = baseTransforms[index]
                    }
                }

                guard hasPendingWork else {
                    rig.modelEntity.jointTransforms = baseTransforms
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

                applyArmSwing(
                    angleRadians: leftAngle,
                    axis: [1, 0, 0],
                    jointIndices: rig.leftArmJointIndices,
                    transforms: &transforms
                )
                applyArmSwing(
                    angleRadians: rightAngle,
                    axis: [-1, 0, 0],
                    jointIndices: rig.rightArmJointIndices,
                    transforms: &transforms
                )
                applyGaitPose(gaitPose, transforms: &transforms, rig: rig)
                rig.modelEntity.jointTransforms = transforms

                try? await Task.sleep(for: .milliseconds(tickMilliseconds))
            }
        }
    }

    private func applyArmSwing(
        angleRadians: Float,
        axis: SIMD3<Float>,
        jointIndices: [Int],
        transforms: inout [Transform]
    ) {
        guard angleRadians != 0, jointIndices.isEmpty == false else { return }
        let delta = simd_quatf(angle: angleRadians, axis: axis)
        for index in jointIndices where index < transforms.count {
            transforms[index].rotation = transforms[index].rotation * delta
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
        for velocity in leftArmPendingVelocities {
            leftArmPulses.append(makePulse(startUptimeNanos: nowNanos, velocity: velocity))
        }
        for velocity in rightArmPendingVelocities {
            rightArmPulses.append(makePulse(startUptimeNanos: nowNanos, velocity: velocity))
        }
        leftArmPendingVelocities.removeAll(keepingCapacity: true)
        rightArmPendingVelocities.removeAll(keepingCapacity: true)
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
        var writeIndex = 0

        for pulse in pulses {
            let dtSeconds = Float(Double(nowUptimeNanos - pulse.startUptimeNanos) / 1_000_000_000.0)
            guard dtSeconds < pulseDurationSeconds else { continue }

            let t = dtSeconds / pulseDurationSeconds
            total += pulse.amplitudeRadians * triangularEaseInOut(t)
            pulses[writeIndex] = pulse
            writeIndex += 1
        }

        if writeIndex < pulses.count {
            pulses.removeLast(pulses.count - writeIndex)
        }
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
            keyboardRoot.addChild(keyEntityFactory.makeEntity(for: key))
        }

        root.addChild(keyboardRoot)
        return root
    }
}
