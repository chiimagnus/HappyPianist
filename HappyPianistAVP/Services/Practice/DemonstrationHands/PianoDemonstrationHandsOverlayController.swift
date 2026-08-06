import Practice
import RealityKit
import SwiftUI

@MainActor
final class PianoDemonstrationHandsOverlayController {
    private let rootEntity: Entity
    private let targetResolver = PianoDemonstrationHandTargetResolver()
    private let poseResolver = PianoDemonstrationHandPoseResolver()
    private var rigs: [PianoDemonstrationHand: PianoDemonstrationHandRig] = [:]
    private var lastTargets = PianoDemonstrationHandTargets.empty
    private var activeMIDINotesByHand: [PianoDemonstrationHand: Set<Int>] = [:]
    private var hasAttachedRoot = false
    private var reduceMotionEnabled = false
    private(set) var requiresReplacement = false

    init(rootEntity: Entity = Entity()) {
        self.rootEntity = rootEntity
        for hand in PianoDemonstrationHand.allCases {
            // ponytail: fixed primitive rig; move to a rigged hand only when anatomy needs exceed guide feedback.
            let rig = PianoDemonstrationHandRig()
            rig.rootEntity.name = "pianoDemonstrationHand.\(hand)"
            rootEntity.addChild(rig.rootEntity)
            rigs[hand] = rig
        }
    }

    func update(
        isEnabled: Bool,
        highlightGuide: PianoHighlightGuide?,
        keyboardGeometry: PianoKeyboardGeometry?,
        reduceMotion: Bool,
        content: RealityViewContent?
    ) {
        guard requiresReplacement == false, isEnabled, let keyboardGeometry else {
            hide()
            return
        }

        if let content {
            attachRootIfNeeded(to: content)
        }
        rootEntity.transform = Transform(matrix: keyboardGeometry.frame.worldFromKeyboard)

        let targets = targetResolver.resolve(
            highlightGuide: highlightGuide,
            keyboardGeometry: keyboardGeometry
        )
        let didEnableReduceMotion = reduceMotion && reduceMotionEnabled == false
        reduceMotionEnabled = reduceMotion
        guard targets != lastTargets || didEnableReduceMotion else { return }

        for hand in PianoDemonstrationHand.allCases {
            let targetsForHand = targets.targets(for: hand)
            if let pose = poseResolver.resolve(hand: hand, targets: targetsForHand),
               let rig = rigs[hand]
            {
                rig.apply(
                    pose: pose,
                    animated: reduceMotion == false && targetsForHand.contains { $0.phase == .triggered }
                )
                activeMIDINotesByHand[hand] = Set(targetsForHand.map(\.midiNote))
            } else if shouldLift(hand: hand, releasedMIDINotes: targets.releasedMIDINotes) {
                rigs[hand]?.lift(animated: reduceMotion == false)
                activeMIDINotesByHand[hand] = []
            } else {
                rigs[hand]?.hide()
                activeMIDINotesByHand[hand] = []
            }
        }

        lastTargets = targets
    }

    func reset() {
        rootEntity.stopAllAnimations()
        for rig in rigs.values {
            rig.hide()
        }
        rigs.removeAll()
        activeMIDINotesByHand.removeAll()
        lastTargets = .empty
        reduceMotionEnabled = false
        rootEntity.children.removeAll(preservingWorldTransforms: false)
        rootEntity.removeFromParent()
        hasAttachedRoot = false
        requiresReplacement = true
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
        for rig in rigs.values {
            rig.hide()
        }
        activeMIDINotesByHand.removeAll()
        lastTargets = .empty
        reduceMotionEnabled = false
        rootEntity.removeFromParent()
        hasAttachedRoot = false
    }
}
