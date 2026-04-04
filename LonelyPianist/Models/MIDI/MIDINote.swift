import Foundation

struct MIDINote: Hashable, Identifiable, Codable {
    let number: Int

    var id: Int { number }

    var name: String {
        let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let pitchClass = max(0, min(127, number)) % 12
        let octave = (max(0, min(127, number)) / 12) - 1
        return "\(noteNames[pitchClass])\(octave)"
    }

    init(_ number: Int) {
        self.number = max(0, min(127, number))
    }
}
