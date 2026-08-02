import Foundation


public struct MusicXMLWrittenPitch: Equatable, Hashable, Sendable {
    public let step: String
    public let octave: Int
    public let alter: Double
    public let accidentalToken: String?

    public init(step: String, octave: Int, alter: Double = 0, accidentalToken: String? = nil) {
        self.step = step.uppercased()
        self.octave = octave
        self.alter = alter
        self.accidentalToken = accidentalToken
    }
}
