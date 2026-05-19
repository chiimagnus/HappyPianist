import Foundation

extension PracticeSessionViewModel {
    func refreshPracticeInputForCurrentState() {
        practiceMIDIInputCoordinator?.refresh(
            for: .init(
                practiceState: self.state,
                autoplayState: self.autoplayState,
                isManualReplayPlaying: self.isManualReplayPlaying,
                currentStepIndex: self.currentStepIndex,
                expectedNotes: self.currentStep?.notes ?? []
            )
        )
    }

    func stopPracticeInput() {
        practiceMIDIInputCoordinator?.stop()
    }

    func refreshAudioRecognitionForCurrentState() {
        refreshPracticeInputForCurrentState()
        guard let currentStep = self.currentStep else {
            audioRecognitionCoordinator?.stop()
            return
        }

        let expectedMIDINotes = uniqueMIDINotes(in: currentStep)
        let expectedByHand = uniqueMIDINotesByHand(in: currentStep)
        let suppressUntil = self.audioRecognitionSuppressUntil.flatMap { $0 > .now ? $0 : nil }
        let handGateBoost = self.handGateState.isNearKeyboard || self.handGateState.hasDownwardMotion

        audioRecognitionCoordinator?.refresh(
            for: .init(
                practiceState: self.state,
                autoplayState: self.autoplayState,
                isManualReplayPlaying: self.isManualReplayPlaying,
                isAudioRecognitionEnabled: isPracticeAudioRecognitionEnabled,
                expectedMIDINotes: expectedMIDINotes,
                expectedRightMIDINotes: expectedByHand.right,
                expectedLeftMIDINotes: expectedByHand.left,
                wrongCandidateMIDINotes: makeWrongCandidateMIDINotes(expectedMIDINotes),
                handGateBoost: handGateBoost,
                isHandSeparatedStepMatchingEnabled: self.isHandSeparatedStepMatchingEnabled,
                suppressUntil: suppressUntil
            )
        )
    }

    func refreshAudioRecognitionFromSettings() {
        self.practiceAudioRecognitionDetectorModeSnapshot = settingsProvider.audioRecognitionDetectorMode
        self.harmonicTemplateTuningProfileSnapshot = Self.profile(for: self.practiceAudioRecognitionDetectorModeSnapshot)
        audioRecognitionService?.configureDetectorMode(
            self.practiceAudioRecognitionDetectorModeSnapshot,
            profile: self.harmonicTemplateTuningProfileSnapshot
        )
        refreshAudioRecognitionForCurrentState()
    }

    func stopAudioRecognition() {
        stopPracticeInput()
        audioRecognitionCoordinator?.stop()
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

    private func makeWrongCandidateMIDINotes(_ expectedMIDINotes: [Int]) -> [Int] {
        var result: Set<Int> = []
        for note in expectedMIDINotes {
            result.insert(note - 2)
            result.insert(note - 1)
            result.insert(note + 1)
            result.insert(note + 2)
        }
        result.subtract(expectedMIDINotes)
        return result.sorted()
    }

    private var isPracticeAudioRecognitionEnabled: Bool {
        audioRecognitionEnabledSnapshot
    }

    var audioRecognitionGenerationForTesting: Int {
        self.audioRecognitionGeneration
    }

    var audioRecognitionSuppressRemainingSeconds: TimeInterval {
        guard let suppressUntil = self.audioRecognitionSuppressUntil else { return 0 }
        return max(0, suppressUntil.timeIntervalSinceNow)
    }

    private static func profile(for _: PracticeAudioRecognitionDetectorMode) -> HarmonicTemplateTuningProfile {
        .lowLatencyDefault
    }
}
