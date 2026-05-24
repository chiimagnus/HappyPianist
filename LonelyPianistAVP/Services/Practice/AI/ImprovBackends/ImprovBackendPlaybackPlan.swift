import Foundation

enum ImprovBackendPlaybackPlan: Equatable {
    case schedule([PracticeSequencerMIDIEvent], backendLatencyMS: Int?)
    case tickRange(maxMeasures: Int)
}
