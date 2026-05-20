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

func uniqueMIDINotesByHand(in step: PracticeStep) -> (right: [Int], left: [Int]) {
    var right: Set<Int> = []
    var left: Set<Int> = []

    for note in step.notes {
        if note.hand == .left {
            left.insert(note.midiNote)
        } else {
            right.insert(note.midiNote)
        }
    }

    return (right: right.sorted(), left: left.sorted())
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
