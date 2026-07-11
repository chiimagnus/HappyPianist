import Foundation

// ponytail: embedded in AVP; extract only when another Swift target needs it.

public enum RuleConstants {
    public static let majorScale: [Int] = [0, 2, 4, 5, 7, 9, 11]
    public static let naturalMinorScale: [Int] = [0, 2, 3, 5, 7, 8, 10]
    public static let majorPentatonic: [Int] = [0, 2, 4, 7, 9]
    public static let minorPentatonic: [Int] = [0, 3, 5, 7, 10]
    public static let bluesScale: [Int] = [0, 3, 5, 6, 7, 10]
    public static let mixolydian: [Int] = [0, 2, 4, 5, 7, 9, 10]
    public static let dorian: [Int] = [0, 2, 3, 5, 7, 9, 10]
    public static let lydian: [Int] = [0, 2, 4, 6, 7, 9, 11]
    public static let phrygian: [Int] = [0, 1, 3, 5, 7, 8, 10]
    public static let harmonicMinor: [Int] = [0, 2, 3, 5, 7, 8, 11]

    public static let chordQualityIntervals: [String: [Int]] = [
        "major": [0, 4, 7],
        "minor": [0, 3, 7],
        "dominant7": [0, 4, 7, 10],
        "major7": [0, 4, 7, 11],
        "minor7": [0, 3, 7, 10],
        "sus4": [0, 5, 7],
        "sus2": [0, 2, 7],
        "diminished": [0, 3, 6],
        "augmented": [0, 4, 8],
    ]

    public static let qualityBase: [String: String] = [
        "dominant7": "major",
        "major7": "major",
        "minor7": "minor",
    ]

    public static let majorTransitions: [Int: [(next: Int, weight: Double)]] = [
        0: [(5, 3.0), (7, 3.0), (9, 2.0), (2, 1.5), (4, 1.0)],
        2: [(7, 3.0), (5, 1.5), (0, 1.0)],
        4: [(9, 2.5), (5, 2.0), (0, 1.0)],
        5: [(7, 3.0), (0, 2.5), (2, 2.0), (9, 1.0)],
        7: [(0, 4.0), (9, 2.0), (5, 1.0)],
        9: [(5, 3.0), (2, 2.5), (7, 2.0), (4, 1.0)],
        11: [(0, 3.0), (4, 1.5)],
    ]

    public static let minorTransitions: [Int: [(next: Int, weight: Double)]] = [
        0: [(5, 3.0), (7, 3.0), (8, 2.0), (3, 2.0), (10, 1.5)],
        2: [(7, 3.0), (5, 1.5)],
        3: [(8, 2.5), (5, 2.0), (0, 1.5)],
        5: [(7, 3.0), (0, 2.5), (8, 1.5)],
        7: [(0, 4.0), (8, 2.0), (5, 1.0)],
        8: [(5, 3.0), (3, 2.0), (2, 1.5)],
        10: [(3, 3.0), (0, 2.5), (5, 1.5)],
    ]

    public struct StyleRule: Equatable, Sendable {
        public struct VelocityRange: Equatable, Sendable {
            public var min: Int
            public var max: Int

            public init(min: Int, max: Int) {
                self.min = min
                self.max = max
            }
        }

        public var label: String
        public var scale: String
        public var density: Double
        public var duration: String
        public var timing: String
        public var velocity: VelocityRange
        public var strongDegrees: [Int]

        public init(
            label: String,
            scale: String,
            density: Double,
            duration: String,
            timing: String,
            velocity: VelocityRange,
            strongDegrees: [Int]
        ) {
            self.label = label
            self.scale = scale
            self.density = density
            self.duration = duration
            self.timing = timing
            self.velocity = velocity
            self.strongDegrees = strongDegrees
        }
    }

    public static let styleRules: [String: StyleRule] = [
        "pop": StyleRule(
            label: "Pop",
            scale: "major_pentatonic",
            density: 1.0,
            duration: "clean",
            timing: "straight",
            velocity: StyleRule.VelocityRange(min: 70, max: 98),
            strongDegrees: [0, 4, 7]
        ),
        "worship": StyleRule(
            label: "Worship",
            scale: "major_add9",
            density: 0.75,
            duration: "legato",
            timing: "straight",
            velocity: StyleRule.VelocityRange(min: 62, max: 92),
            strongDegrees: [0, 2, 7]
        ),
        "rock": StyleRule(
            label: "Rock",
            scale: "minor_blues",
            density: 1.0,
            duration: "short",
            timing: "straight",
            velocity: StyleRule.VelocityRange(min: 88, max: 115),
            strongDegrees: [0, 7, 10]
        ),
        "blues": StyleRule(
            label: "Blues",
            scale: "blues",
            density: 0.85,
            duration: "breathy",
            timing: "swing",
            velocity: StyleRule.VelocityRange(min: 72, max: 108),
            strongDegrees: [0, 3, 7, 10]
        ),
        "funk": StyleRule(
            label: "Funk",
            scale: "minor_pentatonic",
            density: 0.85,
            duration: "staccato",
            timing: "tight_16th",
            velocity: StyleRule.VelocityRange(min: 45, max: 110),
            strongDegrees: [0, 3, 7]
        ),
        "rnb": StyleRule(
            label: "R&B",
            scale: "dorian",
            density: 0.75,
            duration: "short",
            timing: "behind",
            velocity: StyleRule.VelocityRange(min: 58, max: 92),
            strongDegrees: [4, 10, 2]
        ),
        "neo_soul": StyleRule(
            label: "Neo Soul",
            scale: "dorian_color",
            density: 0.65,
            duration: "breathy",
            timing: "behind",
            velocity: StyleRule.VelocityRange(min: 52, max: 88),
            strongDegrees: [4, 10, 2, 5]
        ),
        "country": StyleRule(
            label: "Country",
            scale: "major_pentatonic",
            density: 1.0,
            duration: "clean",
            timing: "straight",
            velocity: StyleRule.VelocityRange(min: 78, max: 104),
            strongDegrees: [0, 4, 7, 9]
        ),
    ]
}
