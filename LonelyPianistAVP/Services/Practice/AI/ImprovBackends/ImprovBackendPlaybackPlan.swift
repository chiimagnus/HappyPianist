import Foundation

enum ImprovBackendPlaybackPlan: Equatable {
    case schedule([PracticeSequencerMIDIEvent])
    case tickRange(maxMeasures: Int)
}
