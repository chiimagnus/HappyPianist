import Foundation

struct PianoGuideKeyHighlight: Equatable, Hashable {
    let midiNote: Int
    let phase: PianoGuideHighlightPhase
    let hand: ScoreHand
}
