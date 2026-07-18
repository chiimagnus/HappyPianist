import Foundation

struct PianoGuideHighlightStyle: Equatable, Hashable {
    let tintToken: PianoGuideHighlightTintToken
    let opacity: Double

    static func resolve(
        staffNumber: Int?,
        phase: PianoGuideHighlightPhase,
        keyKind: PianoKeyKind
    ) -> PianoGuideHighlightStyle {
        let tintToken = PianoGuideHighlightTintToken.resolve(
            staffNumber: staffNumber,
            keyKind: keyKind
        )

        let opacity = switch (keyKind, phase, staffNumber) {
        case (.white, .triggered, _):
            0.75
        case (.white, .active, 1):
            0.48
        case (.white, .active, 2):
            0.55
        case (.white, .active, _):
            0.42
        case (.black, .triggered, _):
            0.95
        case (.black, .active, 1):
            0.95
        case (.black, .active, 2):
            0.92
        case (.black, .active, _):
            0.85
        }

        return PianoGuideHighlightStyle(tintToken: tintToken, opacity: opacity)
    }
}
