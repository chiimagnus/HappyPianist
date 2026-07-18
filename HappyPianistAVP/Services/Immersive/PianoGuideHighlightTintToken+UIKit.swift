import SwiftUI
import UIKit

extension PianoGuideHighlightTintToken {
    var uiColor: UIColor {
        switch self {
        case .rightHandWhiteKey:
            UIColor(Color.yellow)
        case .rightHandBlackKey:
            UIColor(Color.orange)
        case .leftHandKey:
            UIColor(Color.cyan)
        case .unassignedHandKey:
            UIColor(Color.gray)
        }
    }
}
