import Foundation

// MARK: - Pure helpers shared across PracticeSession services & ViewModel

func audioErrorText(for error: Error) -> String {
    if let localized = error as? LocalizedError, let description = localized.errorDescription,
       description.isEmpty == false
    {
        return description
    }
    return String(describing: error)
}

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

extension PracticeSessionStateStore {
    func recordPlaybackError(_ error: Error) {
        guard audioPlaybackErrorMessage == nil else { return }
        audioPlaybackErrorMessage = audioErrorText(for: error)
    }

    func strictTriggerGuideIndex(forStepIndex stepIndex: Int) -> Int? {
        highlightGuides.firstIndex { guide in
            guide.practiceStepIndex == stepIndex && guide.kind == .trigger
        }
    }
}
