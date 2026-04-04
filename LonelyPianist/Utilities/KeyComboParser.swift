import CoreGraphics
import Foundation

struct ParsedKeyCombo {
    let keyCode: CGKeyCode
    let modifiers: CGEventFlags
}

enum KeyComboParseError: LocalizedError {
    case empty
    case noKey
    case invalidToken(String)

    var errorDescription: String? {
        switch self {
        case .empty:
            return "Key combo is empty"
        case .noKey:
            return "Key combo does not contain a key"
        case .invalidToken(let token):
            return "Invalid key token: \(token)"
        }
    }
}

enum KeyComboParser {
    static func parse(_ rawValue: String) throws -> ParsedKeyCombo {
        let normalized = rawValue
            .lowercased()
            .replacingOccurrences(of: " ", with: "")

        guard !normalized.isEmpty else {
            throw KeyComboParseError.empty
        }

        let parts = normalized
            .split(separator: "+")
            .map(String.init)
            .filter { !$0.isEmpty }

        guard !parts.isEmpty else {
            throw KeyComboParseError.empty
        }

        var modifiers: CGEventFlags = []
        var keyCode: CGKeyCode?

        for part in parts {
            if let modifier = Self.modifierFlags(for: part) {
                modifiers.insert(modifier)
                continue
            }

            if let parsedKeyCode = Self.keyCode(for: part) {
                keyCode = parsedKeyCode
                continue
            }

            throw KeyComboParseError.invalidToken(part)
        }

        guard let keyCode else {
            throw KeyComboParseError.noKey
        }

        return ParsedKeyCombo(keyCode: keyCode, modifiers: modifiers)
    }

    private static func modifierFlags(for token: String) -> CGEventFlags? {
        switch token {
        case "cmd", "command", "⌘":
            return .maskCommand
        case "shift", "⇧":
            return .maskShift
        case "ctrl", "control", "⌃":
            return .maskControl
        case "alt", "option", "opt", "⌥":
            return .maskAlternate
        case "fn":
            return .maskSecondaryFn
        default:
            return nil
        }
    }

    private static func keyCode(for token: String) -> CGKeyCode? {
        if token.count == 1 {
            if let char = token.first,
               let code = singleCharacterMap[char] {
                return code
            }
        }

        return namedKeyMap[token]
    }

    private static let namedKeyMap: [String: CGKeyCode] = [
        "return": 36,
        "enter": 36,
        "tab": 48,
        "space": 49,
        "escape": 53,
        "esc": 53,
        "delete": 51,
        "backspace": 51,
        "forwarddelete": 117,
        "up": 126,
        "down": 125,
        "left": 123,
        "right": 124
    ]

    private static let singleCharacterMap: [Character: CGKeyCode] = [
        "a": 0,
        "s": 1,
        "d": 2,
        "f": 3,
        "h": 4,
        "g": 5,
        "z": 6,
        "x": 7,
        "c": 8,
        "v": 9,
        "b": 11,
        "q": 12,
        "w": 13,
        "e": 14,
        "r": 15,
        "y": 16,
        "t": 17,
        "1": 18,
        "2": 19,
        "3": 20,
        "4": 21,
        "6": 22,
        "5": 23,
        "=": 24,
        "9": 25,
        "7": 26,
        "-": 27,
        "8": 28,
        "0": 29,
        "]": 30,
        "o": 31,
        "u": 32,
        "[": 33,
        "i": 34,
        "p": 35,
        "l": 37,
        "j": 38,
        "'": 39,
        "k": 40,
        ";": 41,
        "\\": 42,
        ",": 43,
        "/": 44,
        "n": 45,
        "m": 46,
        ".": 47,
        "`": 50
    ]
}
