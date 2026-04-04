import Foundation

struct RecordedNote: Identifiable, Hashable, Sendable {
    var id: UUID
    var note: Int
    var velocity: Int
    var channel: Int
    var startOffsetSec: TimeInterval
    var durationSec: TimeInterval
}
