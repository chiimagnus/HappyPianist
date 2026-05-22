import Foundation

struct PianoGuideHighlightStyle: Equatable, Hashable {
    let tintToken: PianoGuideHighlightTintToken
    let opacity: Double

    static func resolve(
        hand: ScoreHand,
        phase: PianoGuideHighlightPhase,
        keyKind: PianoKeyKind
    ) -> PianoGuideHighlightStyle {
        let tintToken: PianoGuideHighlightTintToken
        switch hand {
        case .left:
            tintToken = .leftHandKey
        case .right:
            tintToken = (keyKind == .black) ? .rightHandBlackKey : .rightHandWhiteKey
        }

        let opacity: Double
        switch (keyKind, phase, hand) {
        case (.white, .triggered, _):
            opacity = 0.75
        case (.white, .active, .right):
            opacity = 0.48
        case (.white, .active, .left):
            opacity = 0.55
        case (.black, .triggered, _):
            opacity = 0.95
        case (.black, .active, .right):
            opacity = 0.95
        case (.black, .active, .left):
            opacity = 0.92
        }

        return PianoGuideHighlightStyle(tintToken: tintToken, opacity: opacity)
    }
}

