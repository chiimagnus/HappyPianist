import Foundation

public struct RuleNoteEvent: Equatable, Sendable {
    public var note: Int
    public var velocity: Int
    public var time: Double
    public var duration: Double

    public init(note: Int, velocity: Int, time: Double, duration: Double) {
        self.note = note
        self.velocity = velocity
        self.time = time
        self.duration = duration
    }
}
