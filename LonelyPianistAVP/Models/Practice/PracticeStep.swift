import Foundation

struct PracticeStepNote: Equatable, Hashable, Identifiable {
    var id: Int { midiNote }
    let midiNote: Int
    let staff: Int?
}

struct PracticeStep: Equatable, Identifiable {
    var id: Int { tick }
    let tick: Int
    let notes: [PracticeStepNote]
}

struct PracticeStepBuildResult: Equatable {
    let steps: [PracticeStep]
    let unsupportedNoteCount: Int
}
