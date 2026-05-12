import Foundation

extension PracticeSessionViewModel {
    func refreshPracticeInputFromSettings() {
        preferredPracticeInputSourceSnapshot = Self.readPracticeInputSource()
        refreshAudioRecognitionForCurrentState()
    }

    func clearPracticeInputWarning() {
        practiceInputWarningMessage = nil
    }

    func bindBluetoothMIDIStreamsIfNeeded() {
        guard let bluetoothMIDIInputService else { return }
        guard bluetoothMIDIEventsTask == nil else { return }

        bluetoothMIDIEventsTask = Task { [weak self] in
            for await event in bluetoothMIDIInputService.events {
                await MainActor.run {
                    self?.handleBluetoothMIDIEvent(event)
                }
            }
        }
    }

    func startBluetoothMIDIIfNeededForCurrentState() -> Bool {
        guard preferredPracticeInputSourceSnapshot == .bluetoothMIDI else {
            stopBluetoothMIDIIfNeeded()
            activePracticeInputSource = .audio
            return false
        }

        guard let bluetoothMIDIInputService else {
            stopBluetoothMIDIIfNeeded()
            activePracticeInputSource = .audio
            practiceInputWarningMessage = "Bluetooth MIDI 在 Simulator 中不可用，已回退音频识别。"
            return false
        }

        guard audioRecognitionEnabledSnapshot else {
            stopBluetoothMIDIIfNeeded()
            activePracticeInputSource = .audio
            return false
        }

        guard autoplayState == .off, isManualReplayPlaying == false else {
            stopBluetoothMIDIIfNeeded()
            activePracticeInputSource = .audio
            return false
        }

        guard case .guiding = state, currentStep != nil else {
            stopBluetoothMIDIIfNeeded()
            activePracticeInputSource = .audio
            return false
        }

        stopAudioRecognitionServiceOnly()
        activePracticeInputSource = .bluetoothMIDI

        audioStepAttemptAccumulator.setMode(.lowLatency)
        audioRecognitionGeneration += 1
        audioStepAttemptAccumulator.resetForNewStep(generation: audioRecognitionGeneration)

        if isBluetoothMIDIListening {
            bluetoothMIDIInputService.updateGeneration(audioRecognitionGeneration)
            return true
        }

        do {
            let connectedSourceCount = try bluetoothMIDIInputService.start(generation: audioRecognitionGeneration)
            if connectedSourceCount > 0 {
                isBluetoothMIDIListening = true
                return true
            }
            bluetoothMIDIInputService.stop()
            isBluetoothMIDIListening = false
            activePracticeInputSource = .audio
            practiceInputWarningMessage = "未发现可用的 MIDI sources，已回退音频识别。请先连接 Bluetooth MIDI 再重试。"
            return false
        } catch {
            bluetoothMIDIInputService.stop()
            isBluetoothMIDIListening = false
            activePracticeInputSource = .audio
            practiceInputWarningMessage = "Bluetooth MIDI 输入启动失败：\(error.localizedDescription)。已回退音频识别。"
            return false
        }
    }

    func stopBluetoothMIDIIfNeeded() {
        guard isBluetoothMIDIListening else { return }
        bluetoothMIDIInputService?.stop()
        isBluetoothMIDIListening = false
    }

    private func handleBluetoothMIDIEvent(_ event: DetectedNoteEvent) {
        guard preferredPracticeInputSourceSnapshot == .bluetoothMIDI else { return }
        guard activePracticeInputSource == .bluetoothMIDI else { return }
        guard autoplayState == .off else { return }
        guard isManualReplayPlaying == false else { return }
        guard case .guiding = state else { return }
        guard event.generation == audioRecognitionGeneration else { return }
        guard let currentStep else { return }

        let expectedMIDINotes = uniqueMIDINotes(in: currentStep)
        let wrongMIDINotes = Set(Self.makeWrongCandidateMIDINotesForBluetooth(expectedMIDINotes))

        audioStepAttemptAccumulator.register(event: event)
        let matchResult = audioStepAttemptAccumulator.evaluate(
            expectedMIDINotes: expectedMIDINotes,
            wrongCandidateMIDINotes: wrongMIDINotes,
            generation: audioRecognitionGeneration,
            at: event.timestamp,
            handGateBoost: handGateState.isNearKeyboard || handGateState.hasDownwardMotion
        )

        switch matchResult {
            case .matched:
                audioStepAttemptAccumulator.markMatchedAndRequireRearm(
                    expectedMIDINotes: expectedMIDINotes,
                    at: event.timestamp
                )
                advanceToNextStep()
            case .wrong, .insufficient:
                break
        }
    }

    static func readPracticeInputSource() -> Step3PracticeInputSource {
        if let rawValue = UserDefaults.standard.string(forKey: "practiceStep3InputSource"),
           let source = Step3PracticeInputSource(rawValue: rawValue)
        {
            return source
        }
        return .audio
    }

    private static func makeWrongCandidateMIDINotesForBluetooth(_ expectedMIDINotes: [Int]) -> [Int] {
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
}
