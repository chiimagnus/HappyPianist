import Foundation
import Practice

struct PianoDemonstrationFingeringPlan: Equatable {
    let transportGeneration: Int?
    let geometryCacheID: UUID
    let contacts: PianoKeyContactTimeline
    let plan: PianoFingeringPlanner.Plan
}

struct PianoDemonstrationMotionClipSet: Equatable {
    let transportGeneration: Int?
    let geometryCacheID: UUID
    let clips: [PianoHandMotionClip]
    let rejectedOccurrenceIDs: [String]
}
