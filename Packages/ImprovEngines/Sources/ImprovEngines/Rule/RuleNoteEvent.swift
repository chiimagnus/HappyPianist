import Foundation
import ImprovProtocol

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

    public func asDialogueNote() -> ImprovDialogueNote {
        ImprovDialogueNote(note: note, velocity: velocity, time: time, duration: duration)
    }
}
