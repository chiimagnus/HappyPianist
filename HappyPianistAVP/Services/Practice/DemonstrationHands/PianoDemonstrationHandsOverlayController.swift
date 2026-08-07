import Diagnostics
import Foundation
import Practice
import RealityKit
import SwiftUI

@MainActor
final class PianoDemonstrationHandsOverlayController {
    private let rootEntity: Entity
    private let diagnosticsReporter: (any DiagnosticsReporting)?
    private let performanceClock: PerformanceClock
    private let suppressionMinimumResidence: TimeInterval
    private let targetResolver = PianoDemonstrationHandTargetResolver()
    private let poseResolver = PianoDemonstrationHandPoseResolver()
    private let strikeTimeline = PianoDemonstrationStrikeTimeline()
    private var rigs: [PianoDemonstrationHand: PianoDemonstrationHandRig]
    private var lastCoverage = PianoDemonstrationHandCoverage()
    private var activeMIDINotesByHand: [PianoDemonstrationHand: Set<Int>] = [:]
    private var suppressionExpiryByMIDINote: [Int: PerformanceMonotonicInstant] = [:]
    private var loadTask: Task<Void, Never>?
    private var strokeTask: Task<Void, Never>?
    private var strokeGeneration = 0
    private var activeStrikeOccurrenceIDs = Set<String>()
    private var currentStrikeProgress: Float = 1
    private var hasAttachedRoot = false
    private var reduceMotionEnabled = false
    private(set) var requiresReplacement = false

    init(
        rootEntity: Entity = Entity(),
        diagnosticsReporter: (any DiagnosticsReporting)? = nil,
        preloadedRigs: [PianoDemonstrationHand: PianoDemonstrationHandRig]? = nil,
        performanceClock: PerformanceClock = .live(),
        suppressionMinimumResidence: TimeInterval = 0.12
    ) {
        self.rootEntity = rootEntity
        self.diagnosticsReporter = diagnosticsReporter
        self.performanceClock = performanceClock
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

        let coverage = targetResolver.resolve(
            highlightGuide: highlightGuide,
            keyboardGeometry: keyboardGeometry
        )
        let didEnableReduceMotion = reduceMotion && reduceMotionEnabled == false
        reduceMotionEnabled = reduceMotion
        guard coverage != lastCoverage || didEnableReduceMotion else {
            return currentSuppressedMIDINotes()
        }
        lastCoverage = coverage

        if coverage.coveredTargets.isEmpty {
            stopStroke(resetTriggerIDs: true)
            applyCurrentTargets(strikeProgress: 1)
            return currentSuppressedMIDINotes()
        }
        if reduceMotion {
            stopStroke(resetTriggerIDs: false)
            currentStrikeProgress = 1
            applyCurrentTargets(strikeProgress: 1)
            return currentSuppressedMIDINotes()
        }

        let triggeredOccurrenceIDs = Set(
            coverage.coveredTargets.lazy
                .filter { $0.phase == .triggered }
                .map(\.occurrenceID)
        )
        if triggeredOccurrenceIDs.isEmpty == false,
           triggeredOccurrenceIDs != activeStrikeOccurrenceIDs
        {
            activeStrikeOccurrenceIDs = triggeredOccurrenceIDs
            startStroke(velocity: coverage.coveredTargets.map(\.velocity).max() ?? 64)
        } else {
            applyCurrentTargets(strikeProgress: currentStrikeProgress)
        }
        return currentSuppressedMIDINotes()
    }

    func reset() {
        loadTask?.cancel()
        loadTask = nil
        stopStroke(resetTriggerIDs: true)
        rootEntity.stopAllAnimations()
        for rig in rigs.values {
            rig.hide()
        }
        rigs.removeAll()
        activeMIDINotesByHand.removeAll()
        suppressionExpiryByMIDINote.removeAll()
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
                    let rig = try await PianoDemonstrationHandRig.load(hand: hand)
                    guard Task.isCancelled == false, requiresReplacement == false else { return }
                    install(rig: rig, for: hand)
                    applyCurrentTargets(strikeProgress: currentStrikeProgress, hand: hand)
                } catch is CancellationError {
                    return
                } catch {
                    guard Task.isCancelled == false else { return }
                    diagnosticsReporter?.recordSystem(
                        severity: .error,
                        category: .immersiveSpace,
                        stage: "pianoDemonstrationHands.loadAsset",
                        summary: "演示手资源加载失败",
                        reason: "hand=\(hand), error=\(String(describing: type(of: error)))"
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

    private func startStroke(velocity: UInt8) {
        stopStroke(resetTriggerIDs: false)
        strokeGeneration += 1
        let generation = strokeGeneration
        currentStrikeProgress = 0
        applyCurrentTargets(strikeProgress: 0)

        strokeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let startUptime = ProcessInfo.processInfo.systemUptime
            while Task.isCancelled == false {
                let elapsed = ProcessInfo.processInfo.systemUptime - startUptime
                let sample = strikeTimeline.sample(elapsed: elapsed, velocity: velocity)
                currentStrikeProgress = sample.contactProgress
                applyCurrentTargets(strikeProgress: sample.contactProgress)
                if sample.isComplete { break }
                try? await Task.sleep(for: .milliseconds(16))
            }
            guard Task.isCancelled == false, strokeGeneration == generation else { return }
            currentStrikeProgress = 1
            applyCurrentTargets(strikeProgress: 1)
            strokeTask = nil
        }
    }

    private func stopStroke(resetTriggerIDs: Bool) {
        strokeGeneration += 1
        strokeTask?.cancel()
        strokeTask = nil
        if resetTriggerIDs {
            activeStrikeOccurrenceIDs.removeAll()
        }
    }

    private func applyCurrentTargets(
        strikeProgress: Float,
        hand selectedHand: PianoDemonstrationHand? = nil
    ) {
        for hand in PianoDemonstrationHand.allCases where selectedHand == nil || selectedHand == hand {
            let targetsForHand = lastCoverage.coveredTargets(for: hand)
            let handStrikeProgress = targetsForHand.contains {
                $0.phase == .triggered && activeStrikeOccurrenceIDs.contains($0.occurrenceID)
            } ? strikeProgress : 1
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
        stopStroke(resetTriggerIDs: true)
        for rig in rigs.values {
            rig.hide()
        }
        activeMIDINotesByHand.removeAll()
        suppressionExpiryByMIDINote.removeAll()
        lastCoverage = PianoDemonstrationHandCoverage()
        currentStrikeProgress = 1
        reduceMotionEnabled = false
        rootEntity.removeFromParent()
        hasAttachedRoot = false
    }
}
