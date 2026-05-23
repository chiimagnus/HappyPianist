import Foundation

struct PianoGuideHighlightStyle: Equatable, Hashable {
    let tintToken: PianoGuideHighlightTintToken
    let opacity: Double

    static func resolve(
        hand: ScoreHand,
        phase: PianoGuideHighlightPhase,
        keyKind: PianoKeyKind
    ) -> PianoGuideHighlightStyle {
        let tintToken: PianoGuideHighlightTintToken = switch hand {
        case .left:
            .leftHandKey
        case .right:
            (keyKind == .black) ? .rightHandBlackKey : .rightHandWhiteKey
        }

        let opacity = switch (keyKind, phase, hand) {
        case (.white, .triggered, _):
            0.75
        case (.white, .active, .right):
            0.48
        case (.white, .active, .left):
            0.55
        case (.black, .triggered, _):
            0.95
        case (.black, .active, .right):
            0.95
        case (.black, .active, .left):
            0.92
        }

        return PianoGuideHighlightStyle(tintToken: tintToken, opacity: opacity)
    }
}
