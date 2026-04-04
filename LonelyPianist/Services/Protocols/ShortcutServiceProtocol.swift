import Foundation

protocol ShortcutServiceProtocol {
    func runShortcut(named name: String) throws
}
