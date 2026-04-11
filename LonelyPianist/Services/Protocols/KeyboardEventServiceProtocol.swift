import CoreGraphics
import Foundation

protocol KeyboardEventServiceProtocol {
    func typeText(_ text: String) throws
    func sendKeyStroke(_ keyStroke: KeyStroke) throws
}
