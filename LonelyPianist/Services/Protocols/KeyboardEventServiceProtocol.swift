import CoreGraphics
import Foundation

protocol KeyboardEventServiceProtocol {
    func typeText(_ text: String) throws
    func sendKeyCombo(keyCode: CGKeyCode, modifiers: CGEventFlags) throws
}
