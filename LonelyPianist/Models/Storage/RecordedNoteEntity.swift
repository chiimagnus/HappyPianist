import Foundation
import SwiftData

@Model
final class RecordedNoteEntity {
    @Attribute(.unique) var id: UUID
    var note: Int
    var velocity: Int
    var channel: Int
    var startOffsetSec: TimeInterval
    var durationSec: TimeInterval
    var take: RecordingTakeEntity?

    init(
        id: UUID,
        note: Int,
        velocity: Int,
        channel: Int,
        startOffsetSec: TimeInterval,
        durationSec: TimeInterval,
        take: RecordingTakeEntity? = nil
    ) {
        self.id = id
        self.note = note
        self.velocity = velocity
        self.channel = channel
        self.startOffsetSec = startOffsetSec
        self.durationSec = durationSec
        self.take = take
    }
}
