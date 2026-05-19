import Foundation

nonisolated enum DetectedNoteSource: Equatable, Sendable {
    case audio
    case bluetoothMIDI
    case handExactHit
    case handGateBoost
}

nonisolated struct DetectedNoteEvent: Equatable, Sendable {
    let midiNote: Int
    let confidence: Double
    let onsetScore: Double
    let isOnset: Bool
    let timestamp: Date
    let generation: Int
    let source: DetectedNoteSource
}
