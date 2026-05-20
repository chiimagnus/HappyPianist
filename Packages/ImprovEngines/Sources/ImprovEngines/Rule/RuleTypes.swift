import Foundation

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

public struct RuleMeasureChord: Equatable, Sendable {
    public var measureIndex: Int
    public var chord: RuleChordGuess

    public init(measureIndex: Int, chord: RuleChordGuess) {
        self.measureIndex = measureIndex
        self.chord = chord
    }
}

public struct RuleChordProgression: Equatable, Sendable {
    public var chords: [RuleMeasureChord]
    public var tonal: RuleTonalCenter
    public var isLooping: Bool
    public var loopLength: Int

    public init(
        chords: [RuleMeasureChord],
        tonal: RuleTonalCenter,
        isLooping: Bool = false,
        loopLength: Int = 0
    ) {
        self.chords = chords
        self.tonal = tonal
        self.isLooping = isLooping
        self.loopLength = loopLength
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

