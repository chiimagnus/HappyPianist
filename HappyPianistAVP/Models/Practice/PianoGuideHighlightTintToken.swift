import Foundation

enum PianoGuideHighlightTintToken: String, Equatable, Hashable {
    case upperStaffWhiteKey
    case upperStaffBlackKey
    case lowerStaffKey
    case unassignedStaffKey

    static func resolve(staffNumber: Int?, keyKind: PianoKeyKind) -> Self {
        // ponytail: practice renders a piano grand staff; additional staves stay neutral until a palette is defined.
        switch staffNumber {
        case 1:
            keyKind == .black ? .upperStaffBlackKey : .upperStaffWhiteKey
        case 2:
            .lowerStaffKey
        default:
            .unassignedStaffKey
        }
    }
}
