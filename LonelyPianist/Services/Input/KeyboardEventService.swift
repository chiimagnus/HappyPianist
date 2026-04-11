import CoreGraphics
import Foundation
import OSLog

enum KeyboardEventServiceError: LocalizedError {
    case createEventSource
    case createKeyEvent

    var errorDescription: String? {
        switch self {
        case .createEventSource:
            return "Failed to create keyboard event source"
        case .createKeyEvent:
            return "Failed to create keyboard event"
        }
    }
}

struct KeyboardEventService: KeyboardEventServiceProtocol {
    private let logger = Logger(subsystem: "com.chiimagnus.LonelyPianist", category: "KeyboardEvent")

    func typeText(_ text: String) throws {
        guard !text.isEmpty else { return }

        guard let eventSource = CGEventSource(stateID: .hidSystemState) else {
            throw KeyboardEventServiceError.createEventSource
        }

        for character in text {
            try postUnicodeCharacter(character, source: eventSource)
        }
    }

    func sendKeyStroke(_ keyStroke: KeyStroke) throws {
        try postKeyStroke(
            keyCode: CGKeyCode(keyStroke.keyCode),
            modifiers: keyStroke.modifiers.cgEventFlags
        )
    }

    private func postKeyStroke(keyCode: CGKeyCode, modifiers: CGEventFlags) throws {
        guard let eventSource = CGEventSource(stateID: .hidSystemState) else {
            throw KeyboardEventServiceError.createEventSource
        }

        guard let keyDown = CGEvent(
            keyboardEventSource: eventSource,
            virtualKey: keyCode,
            keyDown: true
        ),
        let keyUp = CGEvent(
            keyboardEventSource: eventSource,
            virtualKey: keyCode,
            keyDown: false
        ) else {
            throw KeyboardEventServiceError.createKeyEvent
        }

        keyDown.flags = modifiers
        keyUp.flags = modifiers

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private func postUnicodeCharacter(_ character: Character, source: CGEventSource) throws {
        let units = Array(String(character).utf16)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
            throw KeyboardEventServiceError.createKeyEvent
        }

        keyDown.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
        keyUp.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        logger.debug("Posted unicode character")
    }
}
