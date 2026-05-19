import Foundation

extension PracticeSessionViewModel {
    var currentHighlightedMIDINotes: Set<Int> {
        currentPianoHighlightGuide?.highlightedMIDINotes ?? []
    }

    func currentFingeringByMIDINote(isAutoplayEnabled: Bool) -> [Int: String] {
        guard isAutoplayEnabled else { return [:] }
        return currentPianoHighlightGuide?.fingeringByMIDINote ?? [:]
    }

    func currentTriggeredMIDINotes(isAutoplayEnabled: Bool) -> Set<Int> {
        guard isAutoplayEnabled else { return [] }
        let notes = currentPianoHighlightGuide?.triggeredNotes ?? []
        return Set(notes.map(\.midiNote))
    }

    var currentLeftHandHighlightedMIDINotes: Set<Int> {
        guard let guide = currentPianoHighlightGuide else { return [] }

        var triggeredNotesByMidi: [Int: [PianoHighlightNote]] = [:]
        for note in guide.triggeredNotes {
            triggeredNotesByMidi[note.midiNote, default: []].append(note)
        }

        var activeNotesByMidi: [Int: [PianoHighlightNote]] = [:]
        for note in guide.activeNotes {
            activeNotesByMidi[note.midiNote, default: []].append(note)
        }

        var result: Set<Int> = []
        for midiNote in guide.highlightedMIDINotes {
            let preferredHand = triggeredNotesByMidi[midiNote].flatMap(Self.resolvedHand)
                ?? activeNotesByMidi[midiNote].flatMap(Self.resolvedHand)

            if preferredHand == .left {
                result.insert(midiNote)
            }
        }
        return result
    }

    func setCurrentHighlightGuideForStepIndex(_ stepIndex: Int) {
        highlightGuideController?.setCurrentHighlightGuideForStepIndex(stepIndex)
    }

    func updateHighlightGuideAfterStepAdvance(previousTick: Int, nextStepIndex: Int) {
        highlightGuideController?.updateHighlightGuideAfterStepAdvance(
            previousTick: previousTick,
            nextStepIndex: nextStepIndex
        )
    }

    func strictTriggerGuideIndex(forStepIndex stepIndex: Int) -> Int? {
        stateStore.strictTriggerGuideIndex(forStepIndex: stepIndex)
    }

    private static func resolvedHand(notes: [PianoHighlightNote]) -> ScoreHand? {
        guard notes.isEmpty == false else { return nil }
        if notes.contains(where: { $0.hand == .left }) { return .left }
        return .right
    }
}
