import Foundation

enum ImprovBackendPlaybackPlan: Equatable, Sendable {
    case schedule([PracticeSequencerMIDIEvent])
    case tickRange(maxMeasures: Int)
}

