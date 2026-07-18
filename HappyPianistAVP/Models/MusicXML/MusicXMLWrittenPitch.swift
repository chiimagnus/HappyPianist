import Foundation

struct MusicXMLWrittenPitch: Equatable, Hashable, Sendable {
    let step: String
    let octave: Int
    let alter: Double
    let accidentalToken: String?

    init(step: String, octave: Int, alter: Double = 0, accidentalToken: String? = nil) {
        self.step = step.uppercased()
        self.octave = octave
        self.alter = alter
        self.accidentalToken = accidentalToken
    }
}
