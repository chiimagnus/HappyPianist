import Diagnostics
import Foundation
import MusicXML
import Practice
import RealityKit
import SwiftUI

@MainActor
final class PianoDemonstrationHandsOverlayController {
    private let rootEntity: Entity
    private let diagnosticsReporter: (any DiagnosticsReporting)?
    private let rigLoader: any PianoDemonstrationHandRigLoading
    private let performanceClock: PerformanceClock
    private let suppressionMinimumResidence: TimeInterval
    private let player = PianoHandMotionPlayer()
    private var rigs: [PianoDemonstrationHand: PianoDemonstrationHandRig]
    private var lastSamples: [PianoDemonstrationHand: PianoHandMotionPlayer.Sample] = [:]
    private var activeMIDINotesByHand: [PianoDemonstrationHand: Set<Int>] = [:]
    private var suppressionExpiryByHand: [PianoDemonstrationHand: [Int: PerformanceMonotonicInstant]] = [:]
    private var loadTask: Task<Void, Never>?
    private var hasAttachedRoot = false
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
        motionClipSet: PianoDemonstrationMotionClipSet?,
        timing: PianoDemonstrationHandsTiming,
        keyboardGeometry: PianoKeyboardGeometry?,
        reduceMotion: Bool,
        content: RealityViewContent?
    ) -> Set<Int> {
        guard requiresReplacement == false, isEnabled, reduceMotion == false,
              let keyboardGeometry,
              let motionClipSet
        else {
            hideRenderedHands(clearSuppression: true)
            return []
        }
        if let content {
            attachRootIfNeeded(to: content)
        }
        rootEntity.transform = Transform(matrix: keyboardGeometry.frame.worldFromKeyboard)
        let samples = player.samples(
            clipSet: motionClipSet,
            timing: timing,
            at: performanceClock.now()
        )
        apply(samples: samples)
        return currentSuppressedMIDINotes()
    }

    func reset() {
        loadTask?.cancel()
        loadTask = nil
        for rig in rigs.values {
            rig.hide()
        }
        rigs.removeAll()
        lastSamples.removeAll()
        activeMIDINotesByHand.removeAll()
        suppressionExpiryByHand.removeAll()
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
                    if let sample = lastSamples[hand] {
                        rig.apply(frame: sample.frame)
                    }
                } catch is CancellationError {
                    return
                } catch {
                    guard Task.isCancelled == false else { return }
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

    private func apply(samples: [PianoHandMotionPlayer.Sample]) {
        let samplesByHand: [PianoDemonstrationHand: PianoHandMotionPlayer.Sample] = Dictionary(
            uniqueKeysWithValues: samples.compactMap { sample in
                guard let hand = PianoDemonstrationHand(scoreHand: sample.hand) else { return nil }
                return (hand, sample)
            }
        )
        lastSamples = samplesByHand
        for hand in PianoDemonstrationHand.allCases {
            guard let sample = samplesByHand[hand], let rig = rigs[hand] else {
                rigs[hand]?.hide()
                activeMIDINotesByHand[hand] = []
                continue
            }
            rig.apply(frame: sample.frame)
            activeMIDINotesByHand[hand] = sample.activeMIDINotes
        }
    }

    private func currentSuppressedMIDINotes() -> Set<Int> {
        let now = performanceClock.now()
        var suppressedMIDINotes = Set<Int>()
        for hand in PianoDemonstrationHand.allCases {
            let activeMIDINotes = activeMIDINotesByHand[hand, default: []]
            if activeMIDINotes.isEmpty == false {
                suppressionExpiryByHand[hand] = Dictionary(uniqueKeysWithValues: activeMIDINotes.map {
                    ($0, now.advanced(by: suppressionMinimumResidence))
                })
            } else {
                let remainingExpiryByMIDINote = suppressionExpiryByHand[hand, default: [:]].filter {
                    $0.value > now
                }
                suppressionExpiryByHand[hand] = remainingExpiryByMIDINote.isEmpty ? nil : remainingExpiryByMIDINote
            }
            if let expiryByMIDINote = suppressionExpiryByHand[hand] {
                suppressedMIDINotes.formUnion(expiryByMIDINote.keys)
            }
        }
        return suppressedMIDINotes
    }

    private func hideRenderedHands(clearSuppression: Bool = false) {
        lastSamples.removeAll()
        activeMIDINotesByHand.removeAll()
        if clearSuppression {
            suppressionExpiryByHand.removeAll()
        }
        for rig in rigs.values {
            rig.hide()
        }
    }

    private func attachRootIfNeeded(to content: RealityViewContent) {
        guard hasAttachedRoot == false else { return }
        content.add(rootEntity)
        hasAttachedRoot = true
    }
}

private extension PianoDemonstrationHand {
    init?(scoreHand: ScoreHand) {
        switch scoreHand {
        case .left: self = .left
        case .right: self = .right
        case .unknown: return nil
        }
    }
}
