import Foundation

enum MIDI2ValueMapping {
    nonisolated static func value16To7Bit(_ value: UInt16) -> Int {
        let scaled = (Double(value) / 65535.0 * 127.0).rounded()
        let resolved = max(0, min(127, Int(scaled)))
        guard value != 0 else { return 0 }
        return max(1, resolved)
    }

    nonisolated static func value32To7Bit(_ value: UInt32) -> Int {
        let scaled = (Double(value) / Double(UInt32.max) * 127.0).rounded()
        let resolved = max(0, min(127, Int(scaled)))
        guard value != 0 else { return 0 }
        return max(1, resolved)
    }

    nonisolated static func pitchBend32To14Bit(_ value: UInt32) -> Int {
        let scaled = (Double(value) / Double(UInt32.max) * 16383.0).rounded()
        return max(0, min(16383, Int(scaled)))
    }
}
