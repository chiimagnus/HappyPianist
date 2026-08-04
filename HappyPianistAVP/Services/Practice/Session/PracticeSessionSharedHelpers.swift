import Foundation
import MusicXML
import Practice

// MARK: - Pure helpers shared across PracticeSession services & ViewModel

func uniqueMIDINotesByHand(notes: [PracticeStepNote]) -> (right: [Int], left: [Int], unknown: [Int]) {
    var right: Set<Int> = []
    var left: Set<Int> = []
    var unknown: Set<Int> = []

    for note in notes {
        switch note.hand {
        case .right: right.insert(note.midiNote)
        case .left: left.insert(note.midiNote)
        case .unknown: unknown.insert(note.midiNote)
        }
    }

    return (right: right.sorted(), left: left.sorted(), unknown: unknown.sorted())
}

// MARK: - StateStore convenience helpers

extension PracticeSessionHostState {
    func strictTriggerGuideIndex(forStepIndex stepIndex: Int) -> Int? {
        highlightGuides.firstIndex { guide in
            guide.practiceStepIndex == stepIndex && guide.kind == .trigger
        }
    }
}
