import Foundation

enum MIDINoteParser {
    nonisolated static func parseNotes(_ rawValue: String) -> [Int] {
        let tokens = rawValue
            .replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)

        return tokens.compactMap(parseNote)
    }

    nonisolated static func parseNote(_ rawValue: String) -> Int? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let directValue = Int(trimmed), (0...127).contains(directValue) {
            return directValue
        }

        let pattern = #"^([A-Ga-g])([#b]?)(-?\d{1,2})$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              match.numberOfRanges == 4,
              let letterRange = Range(match.range(at: 1), in: trimmed),
              let accidentalRange = Range(match.range(at: 2), in: trimmed),
              let octaveRange = Range(match.range(at: 3), in: trimmed) else {
            return nil
        }

        let letter = String(trimmed[letterRange]).uppercased()
        let accidental = String(trimmed[accidentalRange])
        let octave = Int(trimmed[octaveRange])

        guard let octave else { return nil }

        let baseSemitone: Int
        switch letter {
        case "C": baseSemitone = 0
        case "D": baseSemitone = 2
        case "E": baseSemitone = 4
        case "F": baseSemitone = 5
        case "G": baseSemitone = 7
        case "A": baseSemitone = 9
        case "B": baseSemitone = 11
        default: return nil
        }

        let accidentalOffset: Int
        switch accidental {
        case "#": accidentalOffset = 1
        case "b": accidentalOffset = -1
        default: accidentalOffset = 0
        }

        let midi = (octave + 1) * 12 + baseSemitone + accidentalOffset
        guard (0...127).contains(midi) else { return nil }

        return midi
    }

    nonisolated static func stringify(notes: [Int], separator: String = " ") -> String {
        notes.map(noteName(for:)).joined(separator: separator)
    }

    nonisolated private static func noteName(for note: Int) -> String {
        let clamped = max(0, min(127, note))
        let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let pitchClass = clamped % 12
        let octave = (clamped / 12) - 1
        return "\(noteNames[pitchClass])\(octave)"
    }
}
