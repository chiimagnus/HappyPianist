import Foundation

/// The calibrated keyboard facts that fingering planning needs without importing App geometry.
public struct PianoFingeringKeyboardLayout: Equatable, Sendable {
    public enum KeyKind: String, Equatable, Sendable {
        case white
        case black
    }

    public struct Key: Equatable, Sendable {
        public let midiNote: Int
        public let kind: KeyKind
        public let localX: Double

        public init(midiNote: Int, kind: KeyKind, localX: Double) {
            self.midiNote = midiNote
            self.kind = kind
            self.localX = localX
        }
    }

    public let keys: [Key]

    public init(keys: [Key]) {
        self.keys = keys.sorted {
            if $0.midiNote != $1.midiNote { return $0.midiNote < $1.midiNote }
            return $0.localX < $1.localX
        }
    }

    /// Returns nil for absent, duplicated, or non-finite calibrated keys.
    public func key(forMIDINote midiNote: Int) -> Key? {
        let matches = keys.filter { $0.midiNote == midiNote }
        guard matches.count == 1, let key = matches.first, key.localX.isFinite else { return nil }
        return key
    }
}
