import Foundation

// ponytail: embedded in AVP; extract only when another Swift target needs it.

public struct RuleTonalCenter: Equatable, Sendable {
    public var rootPC: Int
    public var mode: String

    public init(rootPC: Int, mode: String) {
        self.rootPC = rootPC
        self.mode = mode
    }
}

public struct RuleChordGuess: Equatable, Sendable {
    public var rootPC: Int
    public var quality: String
    public var score: Double
    public var pitchClasses: [Int]

    public init(rootPC: Int, quality: String, score: Double, pitchClasses: [Int]) {
        self.rootPC = rootPC
        self.quality = quality
        self.score = score
        self.pitchClasses = pitchClasses
    }
}



public struct RuleResult: Equatable, Sendable {
    public var notes: [RuleNoteEvent]
    public var timings: [String: Int]
    public var debug: [String: String]

    public init(notes: [RuleNoteEvent], timings: [String: Int], debug: [String: String]) {
        self.notes = notes
        self.timings = timings
        self.debug = debug
    }
}
