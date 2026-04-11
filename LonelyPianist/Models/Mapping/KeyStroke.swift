import AppKit
import CoreGraphics
import Foundation

struct KeyStrokeModifiers: OptionSet, Hashable, Sendable, Codable {
    let rawValue: UInt8

    static let shift = KeyStrokeModifiers(rawValue: 1 << 0)
    static let command = KeyStrokeModifiers(rawValue: 1 << 1)
    static let option = KeyStrokeModifiers(rawValue: 1 << 2)
    static let control = KeyStrokeModifiers(rawValue: 1 << 3)

    private static let supportedMask: UInt8 =
        (1 << 0) |
        (1 << 1) |
        (1 << 2) |
        (1 << 3)

    init(rawValue: UInt8) {
        self.rawValue = rawValue & Self.supportedMask
    }

    var displayPrefix: String {
        var result = ""
        if contains(.command) { result += "\u{2318}" }
        if contains(.option) { result += "\u{2325}" }
        if contains(.control) { result += "\u{2303}" }
        if contains(.shift) { result += "\u{21E7}" }
        return result
    }

    var cgEventFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if contains(.command) { flags.insert(.maskCommand) }
        if contains(.option) { flags.insert(.maskAlternate) }
        if contains(.control) { flags.insert(.maskControl) }
        if contains(.shift) { flags.insert(.maskShift) }
        return flags
    }
}

struct KeyStroke: Codable, Hashable, Sendable {
    var keyCode: UInt16
    var modifiers: KeyStrokeModifiers

    init(keyCode: UInt16, modifiers: KeyStrokeModifiers = []) {
        self.keyCode = keyCode
        self.modifiers = KeyStrokeModifiers(rawValue: modifiers.rawValue)
    }

    init(event: NSEvent) {
        self.init(
            keyCode: event.keyCode,
            modifiers: Self.fromModifierFlags(event.modifierFlags)
        )
    }

    func normalized() -> KeyStroke {
        KeyStroke(keyCode: keyCode, modifiers: modifiers)
    }

    func adding(_ extra: KeyStrokeModifiers) -> KeyStroke {
        KeyStroke(keyCode: keyCode, modifiers: modifiers.union(extra))
    }

    var displayLabel: String {
        "\(modifiers.displayPrefix)\(Self.label(for: keyCode))"
    }

    static func fromModifierFlags(_ flags: NSEvent.ModifierFlags) -> KeyStrokeModifiers {
        var result: KeyStrokeModifiers = []
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.shift) { result.insert(.shift) }
        return result
    }

    static func keyCode(for character: Character) -> UInt16? {
        let lowercase = String(character).lowercased()
        guard lowercase.count == 1, let token = lowercase.first else { return nil }
        return keyCodeByCharacter[token]
    }

    static func label(for keyCode: UInt16) -> String {
        keyLabelByCode[keyCode] ?? String(keyCode)
    }

    private static let keyLabelByCode: [UInt16: String] = [
        0: "A",
        1: "S",
        2: "D",
        3: "F",
        4: "H",
        5: "G",
        6: "Z",
        7: "X",
        8: "C",
        9: "V",
        11: "B",
        12: "Q",
        13: "W",
        14: "E",
        15: "R",
        16: "Y",
        17: "T",
        18: "1",
        19: "2",
        20: "3",
        21: "4",
        22: "6",
        23: "5",
        24: "=",
        25: "9",
        26: "7",
        27: "-",
        28: "8",
        29: "0",
        30: "]",
        31: "O",
        32: "U",
        33: "[",
        34: "I",
        35: "P",
        36: "\u{23CE}",
        37: "L",
        38: "J",
        39: "'",
        40: "K",
        41: ";",
        42: "\\",
        43: ",",
        44: "/",
        45: "N",
        46: "M",
        47: ".",
        48: "\u{21E5}",
        49: "Space",
        50: "`",
        51: "\u{232B}",
        53: "\u{238B}",
        117: "FnDelete",
        123: "\u{2190}",
        124: "\u{2192}",
        125: "\u{2193}",
        126: "\u{2191}"
    ]

    private static let keyCodeByCharacter: [Character: UInt16] = [
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
