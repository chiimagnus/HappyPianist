import AppKit
import Foundation
import OSLog

enum ShortcutServiceError: LocalizedError {
    case invalidName
    case openFailed

    var errorDescription: String? {
        switch self {
        case .invalidName:
            return "Shortcut name is empty"
        case .openFailed:
            return "Failed to launch Shortcuts"
        }
    }
}

struct ShortcutExecutionService: ShortcutServiceProtocol {
    private let logger = Logger(subsystem: "com.chiimagnus.LonelyPianist", category: "Shortcut")

    func runShortcut(named name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ShortcutServiceError.invalidName
        }

        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "shortcuts://run-shortcut?name=\(encoded)") else {
            throw ShortcutServiceError.invalidName
        }

        let success = NSWorkspace.shared.open(url)
        guard success else {
            throw ShortcutServiceError.openFailed
        }

        logger.info("Triggered shortcut: \(trimmed, privacy: .public)")
    }
}
