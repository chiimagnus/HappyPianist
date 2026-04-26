import Foundation

enum DetectedNoteSource: Equatable {
    case audio
    case handExactHit
    case handGateBoost
}

struct DetectedNoteEvent: Equatable {
    let midiNote: Int
    let confidence: Double
    let onsetScore: Double
    let isOnset: Bool
    let timestamp: Date
    let generation: Int
    let source: DetectedNoteSource
}
