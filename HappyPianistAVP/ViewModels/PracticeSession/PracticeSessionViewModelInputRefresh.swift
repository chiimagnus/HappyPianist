import Foundation

extension PracticeSessionViewModel {
    func performanceObservationsStream() -> AsyncStream<PerformanceObservation>? {
        if practiceInputEventSource != nil {
            return practiceMIDIInputService?.performanceObservationsStream()
        }
        if audioRecognitionService != nil {
            return audioRecognitionInputService?.performanceObservationsStream()
        }
        return nil
    }

    func refreshPracticeInputForCurrentState() {
        let expectedNotes = currentStepNotesForPracticeHandMode()
        practiceMIDIInputService?.refresh(
            for: .init(
                practiceState: self.state,
                autoplayState: self.autoplayState,
                isManualReplayPlaying: self.isManualReplayPlaying,
                currentStepIndex: self.currentStepIndex,
                expectedNotes: expectedNotes
            )
        )
    }

    func stopPracticeInput() {
        practiceMIDIInputService?.stop()
    }

    func refreshAudioRecognitionForCurrentState() {
        refreshPracticeInputForCurrentState()
        guard let currentStep = self.currentStep else {
            audioRecognitionInputService?.stop()
            return
        }

        let expectedStepNotes = currentStepNotesForPracticeHandMode(step: currentStep)
        let ignoredMIDINotes = ignoredMIDINotesForPracticeHandMode(step: currentStep)
        let expectedMIDINotes = Set(expectedStepNotes.map(\.midiNote)).sorted()
        let suppressUntil = self.audioRecognitionSuppressUntil.flatMap { $0 > .now ? $0 : nil }
        let handGateBoost = self.handGateState.isNearKeyboard || self.handGateState.hasDownwardMotion

        audioRecognitionInputService?.refresh(
            for: .init(
                practiceState: self.state,
                autoplayState: self.autoplayState,
                isManualReplayPlaying: self.isManualReplayPlaying,
                expectedMIDINotes: expectedMIDINotes,
                wrongCandidateMIDINotes: makeWrongCandidateMIDINotes(
                    expectedMIDINotes,
                    excluding: ignoredMIDINotes
                ),
                handGateBoost: handGateBoost,
                suppressUntil: suppressUntil
            )
        )
    }

    func stopAudioRecognition() {
        stopPracticeInput()
        audioRecognitionInputService?.stop()
    }

    @discardableResult
    func prepareAudioRecognitionSuppressWindowForPlayback() -> Date {
        let suppressUntil = Date.now.addingTimeInterval(audioRecognitionSuppressDuration)
        self.audioRecognitionSuppressUntil = suppressUntil
        audioRecognitionService?.suppressRecognition(
            until: suppressUntil,
            generation: self.audioRecognitionGeneration
        )
        return suppressUntil
    }

    private func makeWrongCandidateMIDINotes(
        _ expectedMIDINotes: [Int],
        excluding excludedMIDINotes: Set<Int>
    ) -> [Int] {
        var result: Set<Int> = []
        for note in expectedMIDINotes {
            result.insert(note - 2)
            result.insert(note - 1)
            result.insert(note + 1)
            result.insert(note + 2)
        }
        result.subtract(expectedMIDINotes)
        if excludedMIDINotes.isEmpty == false {
            result.subtract(excludedMIDINotes)
        }
        return result.sorted()
    }

    var audioRecognitionGenerationForTesting: Int {
        self.audioRecognitionGeneration
    }

    private func currentStepNotesForPracticeHandMode() -> [PracticeStepNote] {
        guard let step = self.currentStep else { return [] }
        return currentStepNotesForPracticeHandMode(step: step)
    }

    private func currentStepNotesForPracticeHandMode(step: PracticeStep) -> [PracticeStepNote] {
        let mode = self.practiceHandMode
        if mode == .both { return step.notes }
        return step.notes.filter { note in
            mode.allows(hand: note.hand)
        }
    }

    private func ignoredMIDINotesForPracticeHandMode(step: PracticeStep) -> Set<Int> {
        let mode = self.practiceHandMode
        guard mode != .both else { return [] }
        return Set(step.notes.filter { note in
            mode.allows(hand: note.hand) == false
        }.map(\.midiNote))
    }
}
