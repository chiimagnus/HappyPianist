import SwiftUI

extension PianoGuideHighlightTintToken {
    var swiftUIColor: Color {
        switch self {
        case .rightHandWhiteKey:
            .yellow
        case .rightHandBlackKey:
            .orange
        case .leftHandKey:
            .cyan
        }
    }
}

