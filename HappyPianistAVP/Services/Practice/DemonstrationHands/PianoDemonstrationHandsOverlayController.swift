import Diagnostics
import Foundation
import Practice
import RealityKit
import SwiftUI

@MainActor
final class PianoDemonstrationHandsOverlayController {
    private struct HandStrokeRuntime {
        var task: Task<Void, Never>?
        var generation = 0
        var progress: Float = 1
        var occurrenceIDs = Set<String>()
        var velocity: UInt8 = 64
    }

    private let rootEntity: Entity
    private let diagnosticsReporter: (any DiagnosticsReporting)?
    private let rigLoader: any PianoDemonstrationHandRigLoading
    private let performanceClock: PerformanceClock
    private let suppressionMinimumResidence: TimeInterval
    private let targetResolver = PianoDemonstrationHandTargetResolver()
    private let poseResolver = PianoDemonstrationHandPoseResolver()
    private let strikeScheduler: PianoDemonstrationStrikeScheduler
    private var rigs: [PianoDemonstrationHand: PianoDemonstrationHandRig]
    private var lastResolvedCoverage = PianoDemonstrationHandCoverage()
    private var lastCoverage = PianoDemonstrationHandCoverage()
    private var activeMIDINotesByHand: [PianoDemonstrationHand: Set<Int>] = [:]
    private var suppressionExpiryByMIDINote: [Int: PerformanceMonotonicInstant] = [:]
    private var strokeRuntimeByHand: [PianoDemonstrationHand: HandStrokeRuntime] = [:]
    private var loadTask: Task<Void, Never>?
    private var hasAttachedRoot = false
    private var reduceMotionEnabled = false
    private(set) var requiresReplacement = false

    init(
        rootEntity: Entity = Entity(),
        diagnosticsReporter: (any DiagnosticsReporting)? = nil,
        preloadedRigs: [PianoDemonstrationHand: PianoDemonstrationHandRig]? = nil,
        rigLoader: any PianoDemonstrationHandRigLoading = PackagedPianoDemonstrationHandRigLoader(),
        performanceClock: PerformanceClock = .live(),
        suppressionMinimumResidence: TimeInterval = 0.12
    ) {
        self.rootEntity = rootEntity
        self.diagnosticsReporter = diagnosticsReporter
        self.rigLoader = rigLoader
        self.performanceClock = performanceClock
        self.strikeScheduler = PianoDemonstrationStrikeScheduler(performanceClock: performanceClock)
        self.suppressionMinimumResidence = max(0, suppressionMinimumResidence)
        rigs = preloadedRigs ?? [:]
        for (hand, rig) in rigs {
            install(rig: rig, for: hand)
        }
        if preloadedRigs == nil {
            startLoadingRigs()
        }
    }

    @discardableResult
    func update(
        isEnabled: Bool,
        highlightGuide: PianoHighlightGuide?,
        keyboardGeometry: PianoKeyboardGeometry?,
        reduceMotion: Bool,
        content: RealityViewContent?
    ) -> Set<Int> {
        guard requiresReplacement == false, isEnabled, let keyboardGeometry else {
            hide()
            return []
        }

        if let content {
            attachRootIfNeeded(to: content)
        }
        rootEntity.transform = Transform(matrix: keyboardGeometry.frame.worldFromKeyboard)

        let resolvedCoverage = targetResolver.resolve(
            highlightGuide: highlightGuide,
            keyboardGeometry: keyboardGeometry
        )
        lastResolvedCoverage = resolvedCoverage
        let coverage = resolvedCoverage.limitedToAvailableHands(Set(rigs.keys))
        let didEnableReduceMotion = reduceMotion && reduceMotionEnabled == false
        reduceMotionEnabled = reduceMotion
        guard coverage != lastCoverage || didEnableReduceMotion else {
            return currentSuppressedMIDINotes()
        }
        lastCoverage = coverage

        if coverage.coveredTargets.isEmpty {
            stopAllStrokes(resetTriggerIDs: true)
            applyCurrentTargets()
            return currentSuppressedMIDINotes()
        }
        if reduceMotion {
            stopAllStrokes(resetTriggerIDs: false)
            for hand in PianoDemonstrationHand.allCases {
                var runtime = strokeRuntime(for: hand)
                runtime.progress = 1
                strokeRuntimeByHand[hand] = runtime
            }
            applyCurrentTargets()
            return currentSuppressedMIDINotes()
        }

        for hand in PianoDemonstrationHand.allCases {
            let targetsForHand = coverage.coveredTargets(for: hand)
            guard targetsForHand.isEmpty == false else {
                stopStroke(for: hand, resetTriggerIDs: true)
                applyCurrentTargets(hand: hand)
                continue
            }

            let triggeredOccurrenceIDs = Set(
                targetsForHand.lazy
                    .filter { $0.phase == .triggered }
                    .map(\.occurrenceID)
            )
            if triggeredOccurrenceIDs.isEmpty == false,
               triggeredOccurrenceIDs != strokeRuntime(for: hand).occurrenceIDs
            {
                startStroke(for: hand, targets: targetsForHand)
            } else {
                applyCurrentTargets(hand: hand)
            }
        }
        return currentSuppressedMIDINotes()
    }

    func reset() {
        loadTask?.cancel()
        loadTask = nil
        stopAllStrokes(resetTriggerIDs: true)
        strokeRuntimeByHand.removeAll()
        rootEntity.stopAllAnimations()
        for rig in rigs.values {
            rig.hide()
        }
        rigs.removeAll()
        activeMIDINotesByHand.removeAll()
        suppressionExpiryByMIDINote.removeAll()
        lastResolvedCoverage = PianoDemonstrationHandCoverage()
        lastCoverage = PianoDemonstrationHandCoverage()
        reduceMotionEnabled = false
        rootEntity.children.removeAll(preservingWorldTransforms: false)
        rootEntity.removeFromParent()
        hasAttachedRoot = false
        requiresReplacement = true
    }

    private func startLoadingRigs() {
        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { loadTask = nil }
            for hand in PianoDemonstrationHand.allCases {
                guard Task.isCancelled == false else { return }
                do {
                    let rig = try await rigLoader.load(hand: hand)
                    guard Task.isCancelled == false, requiresReplacement == false else { return }
                    install(rig: rig, for: hand)
                    lastCoverage = lastResolvedCoverage.limitedToAvailableHands(Set(rigs.keys))
                    applyCurrentTargets(hand: hand)
                } catch is CancellationError {
                    return
                } catch {
                    guard Task.isCancelled == false else { return }
                    lastCoverage = lastResolvedCoverage.limitedToAvailableHands(Set(rigs.keys))
                    diagnosticsReporter?.recordSystem(
                        severity: .error,
                        category: .immersiveSpace,
                        stage: "pianoDemonstrationHands.loadAsset",
                        summary: "演示手资源加载失败",
                        reason: "hand=\(hand), reason=assetUnavailable, error=\(String(describing: type(of: error)))"
                    )
                }
            }
        }
    }

    private func install(rig: PianoDemonstrationHandRig, for hand: PianoDemonstrationHand) {
        rig.rootEntity.name = "pianoDemonstrationHand.\(hand)"
        rootEntity.addChild(rig.rootEntity)
        rigs[hand] = rig
    }

    private func startStroke(
        for hand: PianoDemonstrationHand,
        targets: [PianoDemonstrationHandTarget]
    ) {
        stopStroke(for: hand, resetTriggerIDs: false)
        var runtime = strokeRuntime(for: hand)
        runtime.progress = 0
        runtime.occurrenceIDs = Set(
            targets.lazy
                .filter { $0.phase == .triggered }
                .map(\.occurrenceID)
        )
        runtime.velocity = targets.map(\.velocity).max() ?? 64
        let generation = runtime.generation
        strokeRuntimeByHand[hand] = runtime
        applyCurrentTargets(hand: hand)

        let startUptime = ProcessInfo.processInfo.systemUptime
        let startInstant = PerformanceMonotonicInstant(seconds: startUptime)
        let onset = startInstant.advanced(by: strikeScheduler.preRollDuration(
            velocity: runtime.velocity,
            handTravelDistanceMeters: 0
        ))
        let occurrence = PianoDemonstrationStrikeScheduler.Occurrence(
            id: runtime.occurrenceIDs.sorted().joined(separator: "|"),
            hand: hand,
            onset: onset,
            release: onset,
            velocity: runtime.velocity,
            handTravelDistanceMeters: 0
        )
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            while Task.isCancelled == false {
                guard var runtime = strokeRuntimeByHand[hand], runtime.generation == generation else {
                    return
                }
                let instant = PerformanceMonotonicInstant(
                    seconds: ProcessInfo.processInfo.systemUptime
                )
                let sample = strikeScheduler.sample(occurrence, at: instant)
                runtime.progress = sample.contactProgress
                strokeRuntimeByHand[hand] = runtime
                applyCurrentTargets(hand: hand)
                if sample.isComplete { break }
                try? await Task.sleep(for: .milliseconds(16))
            }
            guard Task.isCancelled == false,
                  var runtime = strokeRuntimeByHand[hand],
                  runtime.generation == generation
            else {
                return
            }
            runtime.progress = 1
            runtime.task = nil
            strokeRuntimeByHand[hand] = runtime
            applyCurrentTargets(hand: hand)
        }

        runtime = strokeRuntime(for: hand)
        guard runtime.generation == generation else {
            task.cancel()
            return
        }
        runtime.task = task
        strokeRuntimeByHand[hand] = runtime
    }

    private func stopStroke(
        for hand: PianoDemonstrationHand,
        resetTriggerIDs: Bool
    ) {
        var runtime = strokeRuntime(for: hand)
        runtime.generation &+= 1
        runtime.task?.cancel()
        runtime.task = nil
        if resetTriggerIDs {
            runtime.progress = 1
            runtime.occurrenceIDs.removeAll()
            runtime.velocity = 64
        }
        strokeRuntimeByHand[hand] = runtime
    }

    private func stopAllStrokes(resetTriggerIDs: Bool) {
        for hand in PianoDemonstrationHand.allCases {
            stopStroke(for: hand, resetTriggerIDs: resetTriggerIDs)
        }
    }

    private func strokeRuntime(for hand: PianoDemonstrationHand) -> HandStrokeRuntime {
        strokeRuntimeByHand[hand] ?? HandStrokeRuntime()
    }

    private func applyCurrentTargets(hand selectedHand: PianoDemonstrationHand? = nil) {
        for hand in PianoDemonstrationHand.allCases where selectedHand == nil || selectedHand == hand {
            let targetsForHand = lastCoverage.coveredTargets(for: hand)
            let runtime = strokeRuntime(for: hand)
            let handStrikeProgress = targetsForHand.contains {
                $0.phase == .triggered && runtime.occurrenceIDs.contains($0.occurrenceID)
            } ? runtime.progress : 1
            if let pose = poseResolver.resolve(
                hand: hand,
                targets: targetsForHand,
                strikeProgress: handStrikeProgress
            ), let rig = rigs[hand] {
                rig.apply(pose: pose)
                activeMIDINotesByHand[hand] = Set(targetsForHand.map(\.midiNote))
            } else if shouldLift(hand: hand, releasedMIDINotes: lastCoverage.releasedMIDINotes) {
                rigs[hand]?.lift(animated: reduceMotionEnabled == false)
                activeMIDINotesByHand[hand] = []
            } else {
                rigs[hand]?.hide()
                activeMIDINotesByHand[hand] = []
            }
        }
    }

    private func currentSuppressedMIDINotes() -> Set<Int> {
        let now = performanceClock.now()
        let activeMIDINotes = activeMIDINotesByHand.values.reduce(into: Set<Int>()) {
            $0.formUnion($1)
        }
        for midiNote in activeMIDINotes {
            suppressionExpiryByMIDINote[midiNote] = now.advanced(by: suppressionMinimumResidence)
        }
        let expiredMIDINotes = suppressionExpiryByMIDINote.compactMap { midiNote, expiry in
            activeMIDINotes.contains(midiNote) == false && expiry <= now ? midiNote : nil
        }
        for midiNote in expiredMIDINotes {
            suppressionExpiryByMIDINote[midiNote] = nil
        }
        return Set(suppressionExpiryByMIDINote.keys)
    }

    private func attachRootIfNeeded(to content: RealityViewContent) {
        guard hasAttachedRoot == false else { return }
        content.add(rootEntity)
        hasAttachedRoot = true
    }

    private func shouldLift(
        hand: PianoDemonstrationHand,
        releasedMIDINotes: Set<Int>
    ) -> Bool {
        guard let activeMIDINotes = activeMIDINotesByHand[hand], activeMIDINotes.isEmpty == false else {
            return false
        }
        return activeMIDINotes.isDisjoint(with: releasedMIDINotes) == false
    }

    private func hide() {
        stopAllStrokes(resetTriggerIDs: true)
        strokeRuntimeByHand.removeAll()
        for rig in rigs.values {
            rig.hide()
        }
        activeMIDINotesByHand.removeAll()
        suppressionExpiryByMIDINote.removeAll()
        lastResolvedCoverage = PianoDemonstrationHandCoverage()
        lastCoverage = PianoDemonstrationHandCoverage()
        reduceMotionEnabled = false
        rootEntity.removeFromParent()
        hasAttachedRoot = false
    }
}
