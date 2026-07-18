import SwiftUI

extension PianoGuideHighlightTintToken {
    var swiftUIColor: Color {
        switch self {
        case .upperStaffWhiteKey:
            .yellow
        case .upperStaffBlackKey:
            .orange
        case .lowerStaffKey:
            .cyan
        case .unassignedStaffKey:
            .gray
        }
    }
}
