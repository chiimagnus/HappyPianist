import SwiftUI
import UIKit

extension PianoGuideHighlightTintToken {
    var uiColor: UIColor {
        switch self {
        case .upperStaffWhiteKey:
            UIColor(Color.yellow)
        case .upperStaffBlackKey:
            UIColor(Color.orange)
        case .lowerStaffKey:
            UIColor(Color.cyan)
        case .unassignedStaffKey:
            UIColor(Color.gray)
        }
    }
}
