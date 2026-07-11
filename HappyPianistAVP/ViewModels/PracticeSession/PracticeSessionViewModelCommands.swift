import Foundation

extension PracticeSessionViewModel {
    var audioErrorMessage: String? {
        self.audioRecognitionErrorMessage ?? self.audioPlaybackErrorMessage
    }

    var currentStep: PracticeStep? {
        guard self.state != .completed else { return nil }
        guard self.steps.indices.contains(self.currentStepIndex) else { return nil }
        guard self.activeRange?.contains(stepIndex: self.currentStepIndex) ?? true else { return nil }
        return self.steps[self.currentStepIndex]
    }

    var currentPianoHighlightGuide: PianoHighlightGuide? {
        guard let currentHighlightGuideIndex = self.currentHighlightGuideIndex else { return nil }
        guard self.highlightGuides.indices.contains(currentHighlightGuideIndex) else { return nil }
        return self.highlightGuides[currentHighlightGuideIndex]
    }

    var currentMusicXMLAttributeSummaryText: String? {
        guard let attributeTimeline = self.attributeTimeline else { return nil }
        guard let currentStep = self.currentStep else { return nil }

        let tick = currentStep.tick

        var parts: [String] = []
        if let time = attributeTimeline.timeSignature(atTick: tick) {
            parts.append("\(time.beats)/\(time.beatType)")
        }
        if let key = attributeTimeline.keySignature(atTick: tick) {
            let fifths = key.fifths
            let token = fifths >= 0 ? "+\(fifths)" : "\(fifths)"
            parts.append("Key \(token)")
        }

        let rh = attributeTimeline.clef(atTick: tick, staffNumber: 1).flatMap { Self.clefToken(for: $0) }
        let lh = attributeTimeline.clef(atTick: tick, staffNumber: 2).flatMap { Self.clefToken(for: $0) }
        let clefTokens = [rh, lh].compactMap(\.self)
        if clefTokens.isEmpty == false {
            parts.append("Clef \(clefTokens.joined(separator: "/"))")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var notationMeasureSpans: [MusicXMLMeasureSpan] {
        self.activeRange?.measureSpans ?? self.measureSpans
    }

    var activeHighlightGuides: [PianoHighlightGuide] {
        guard let activeRange else { return highlightGuides }
        return highlightGuides.filter { activeRange.contains(tick: $0.tick) }
    }

    var currentGrandStaffNotationContext: GrandStaffNotationContext? {
        guard let attributeTimeline = self.attributeTimeline else { return nil }

        let tick = self.currentPianoHighlightGuide?.tick ?? self.currentStep?.tick ?? 0

        let trebleClefEvent = attributeTimeline.clef(atTick: tick, staffNumber: 1)
        let trebleClef = trebleClefEvent.flatMap { Self.notationClefSymbol(for: $0) } ?? "\u{E050}"
        let trebleClefSignToken = trebleClefEvent?.signToken
        let trebleClefLine = trebleClefEvent?.line

        let bassClefEvent = attributeTimeline.clef(atTick: tick, staffNumber: 2)
        let bassClef = bassClefEvent.flatMap { Self.notationClefSymbol(for: $0) } ?? "\u{E062}"
        let bassClefSignToken = bassClefEvent?.signToken
        let bassClefLine = bassClefEvent?.line

        let keySignatureEvent = attributeTimeline.keySignature(atTick: tick)
        let keySignatureText = keySignatureEvent
            .flatMap { Self.notationKeySignatureText(fifths: $0.fifths) }
        let keySignatureFifths = keySignatureEvent?.fifths
        let timeSignatureText = attributeTimeline.timeSignature(atTick: tick).map { "\($0.beats)/\($0.beatType)" }

        return GrandStaffNotationContext(
            trebleClefSymbol: trebleClef,
            bassClefSymbol: bassClef,
            trebleClefSignToken: trebleClefSignToken,
            trebleClefLine: trebleClefLine,
            bassClefSignToken: bassClefSignToken,
            bassClefLine: bassClefLine,
            keySignatureText: keySignatureText,
            keySignatureFifths: keySignatureFifths,
            timeSignatureText: timeSignatureText
        )
    }

    private static func clefToken(for event: MusicXMLClefEvent) -> String? {
        guard let sign = event.signToken, sign.isEmpty == false else { return nil }
        switch sign.uppercased() {
        case "G":
            return "G"
        case "F":
            return "F"
        case "C":
            return "C"
        default:
            return sign
        }
    }

    private static func notationClefSymbol(for event: MusicXMLClefEvent) -> String? {
        guard let sign = event.signToken, sign.isEmpty == false else { return nil }
        switch sign.uppercased() {
        case "G":
            return "\u{E050}" // SMuFL gClef
        case "F":
            return "\u{E062}" // SMuFL fClef
        case "C":
            return "\u{E05C}" // SMuFL cClef
        default:
            return nil
        }
    }

    private static func notationKeySignatureText(fifths: Int) -> String? {
        if fifths == 0 {
            return nil
        }
        if fifths > 0 {
            return String(repeating: "\u{E262}", count: min(fifths, 7)) // SMuFL accidentalSharp
        }
        return String(repeating: "\u{E260}", count: min(abs(fifths), 7)) // SMuFL accidentalFlat
    }

    var isMusicXMLSlurActive: Bool {
        guard let slurTimeline = self.slurTimeline else { return false }
        guard let currentStep = self.currentStep else { return false }
        return slurTimeline.isActive(atTick: currentStep.tick)
    }

    var manualAdvanceMode: ManualAdvanceMode {
        stateStore.activeManualAdvanceMode
    }

    var canReplayCurrentManualUnit: Bool {
        self.currentStep != nil
    }

    private var manualAdvanceContext: ManualAdvanceContext {
        ManualAdvanceContext(
            currentStepIndex: self.currentStepIndex,
            steps: self.steps,
            measureSpans: self.activeRange?.measureSpans ?? self.measureSpans,
            activeRange: self.activeRange
        )
    }

    private var manualAdvanceStrategy: ManualAdvanceStrategyProtocol {
        switch manualAdvanceMode {
        case .step:
            StepManualAdvanceStrategy()
        case .measure:
            MeasureManualAdvanceStrategy()
        }
    }

    func recordAttemptOutcome(_ outcome: StepAttemptMatchResult, at timestamp: Date = .now) {
        lastAttemptOutcome = outcome
        guard let identity = songIdentity,
              let configuration = activeRoundConfiguration,
              let measureIndex
        else {
            return
        }

        let result = attemptReducer.reduceAttempt(
            progress: sessionProgress,
            reductionState: attemptReductionState,
            outcome: outcome,
            stepIndex: currentStepIndex,
            identity: identity,
            configuration: configuration,
            roundGeneration: roundGeneration,
            measureIndex: measureIndex,
            timestamp: timestamp
        )
        sessionProgress = result.progress
        attemptReductionState = result.reductionState
        lastSessionFact = result.fact
    }

    func recordPassageRestart(at timestamp: Date = .now) {
        guard let identity = songIdentity, let configuration = activeRoundConfiguration else { return }
        let result = attemptReducer.reducePassageRestart(
            progress: sessionProgress,
            identity: identity,
            configuration: configuration,
            roundGeneration: roundGeneration,
            timestamp: timestamp
        )
        sessionProgress = result.progress
        attemptReductionState = result.reductionState
        lastSessionFact = result.fact
    }

    func recordPassageCompletion(at timestamp: Date = .now) {
        guard let identity = songIdentity, let configuration = activeRoundConfiguration else { return }
        let result = attemptReducer.reducePassageCompletion(
            progress: sessionProgress,
            reductionState: attemptReductionState,
            identity: identity,
            configuration: configuration,
            roundGeneration: roundGeneration,
            timestamp: timestamp
        )
        sessionProgress = result.progress
        attemptReductionState = result.reductionState
        lastSessionFact = result.fact
    }

    @discardableResult
    func applyPendingRoundConfiguration() -> Bool {
        stopManualReplayTask()
        stopAutoplayTask()
        stopAutoplayAudio()
        stopAudioRecognition()
        let routingChanged = roundConfigurationController.applyPending()
        rebuildActiveRange()
        currentStepIndex = activeRange?.firstStepIndex ?? 0
        state = steps.isEmpty ? .idle : .ready
        recordPassageRestart()
        setCurrentHighlightGuideForStepIndex(currentStepIndex)
        rebuildAutoplayTimeline()
        refreshAudioRecognitionForCurrentState()
        refreshPracticeInputForCurrentState()
        return routingChanged
    }

    func rebuildActiveRange() {
        guard let configuration = activeRoundConfiguration, let measureIndex else {
            activeRange = nil
            activeRangeDiagnostic = nil
            return
        }
        do {
            activeRange = try measureIndex.resolve(configuration.passage)
            activeRangeDiagnostic = nil
        } catch let diagnostic as PracticeMeasureIndexDiagnostic {
            activeRange = nil
            activeRangeDiagnostic = diagnostic
        } catch {
            activeRange = nil
            activeRangeDiagnostic = .passageBoundaryNotFound
        }
    }

    func setSteps(
        _ steps: [PracticeStep],
        tempoMap: MusicXMLTempoMap,
        pedalTimeline: MusicXMLPedalTimeline? = nil,
        fermataTimeline: MusicXMLFermataTimeline? = nil,
        attributeTimeline: MusicXMLAttributeTimeline? = nil,
        slurTimeline: MusicXMLSlurTimeline? = nil,
        highlightGuides: [PianoHighlightGuide] = [],
        measureSpans: [MusicXMLMeasureSpan] = []
    ) {
        if self.state == .completed, self.steps == steps, steps.isEmpty == false {
            return
        }

        let shouldResetProgress = self.steps != steps
        stopManualReplayTask()
        stopAutoplayTask()
        stopAutoplayAudio()
        stopAudioRecognition()
        highlightGuideController?.stopTransition()
        chordAttemptAccumulator.reset()

        self.steps = steps
        self.tempoMap = tempoMap
        self.measureSpans = measureSpans
        if let firstMeasure = measureSpans.first,
           let lastMeasure = measureSpans.last,
           let passage = PracticePassage(start: firstMeasure.occurrenceID, end: lastMeasure.occurrenceID)
        {
            roundConfigurationController.installInitialPassageIfNeeded(passage)
        }
        measureIndex = PracticeMeasureIndex(steps: steps, measureSpans: measureSpans)
        rebuildActiveRange()
        self.pedalTimeline = pedalTimeline
        self.fermataTimeline = fermataTimeline
        self.attributeTimeline = attributeTimeline
        self.slurTimeline = slurTimeline
        self.highlightGuides = highlightGuides
        rebuildAutoplayTimeline()
        self.currentHighlightGuideIndex = nil

        if shouldResetProgress {
            self.currentStepIndex = activeRange?.firstStepIndex ?? 0
            self.currentHighlightGuideIndex = nil
            self.pressedNotes.removeAll()
        }

        let tick = steps.indices.contains(self.currentStepIndex) ? steps[self.currentStepIndex].tick : 0
        self.isSustainPedalDown = pedalTimeline?.isDown(atTick: tick) ?? false

        if steps.isEmpty {
            self.state = .idle
        } else if self.state != .completed {
            self.state = .ready
        }

        refreshAudioRecognitionForCurrentState()
    }

    func applyKeyboardGeometry(_ keyboardGeometry: PianoKeyboardGeometry, calibration: PianoCalibration) {
        self.calibration = calibration
        self.keyboardGeometry = keyboardGeometry
        if self.steps.isEmpty == false, self.state != .completed, self.state != .guiding(stepIndex: self.currentStepIndex) {
            self.state = .ready
        }
    }

    func applyVirtualKeyboardGeometry(_ keyboardGeometry: PianoKeyboardGeometry) {
        self.keyboardGeometry = keyboardGeometry
        if self.steps.isEmpty == false, self.state != .completed, self.state != .guiding(stepIndex: self.currentStepIndex) {
            self.state = .ready
        }
    }

    func updateLatestNoteOnMIDINotes(_ midiNotes: Set<Int>) {
        self.latestNoteOnMIDINotes = midiNotes
    }

    func clearCalibration() {
        self.calibration = nil
        self.keyboardGeometry = nil
        self.pressedNotes.removeAll()
        self.latestNoteOnMIDINotes.removeAll()
        self.latestKeyContactResult = KeyContactResult(down: [], started: [], ended: [])
        virtualPianoInputController?.stop()
        realPianoContactDetectionService.reset()
        handPianoActivityGate.reset()
        self.handGateState = HandGateState(
            isNearKeyboard: false,
            hasDownwardMotion: false,
            exactPressedNotes: [],
            confidenceBoost: 0
        )
    }

    func resetSession() {
        stopManualReplayTask()
        stopAutoplayTask()
        stopAutoplayAudio()
        stopAudioRecognition()
        chordAttemptAccumulator.reset()

        self.songIdentity = nil
        self.steps = []
        self.tempoMap = MusicXMLTempoMap(tempoEvents: [])
        self.measureSpans = []
        self.pedalTimeline = nil
        self.fermataTimeline = nil
        self.attributeTimeline = nil
        self.slurTimeline = nil
        self.highlightGuides = []
        self.currentHighlightGuideIndex = nil
        highlightGuideController?.stopTransition()

        self.calibration = nil
        self.keyboardGeometry = nil
        self.pressedNotes.removeAll()
        self.latestNoteOnMIDINotes.removeAll()
        self.latestKeyContactResult = KeyContactResult(down: [], started: [], ended: [])
        virtualPianoInputController?.stop()
        realPianoContactDetectionService.reset()
        self.isSustainPedalDown = false

        self.audioRecognitionErrorMessage = nil
        self.audioPlaybackErrorMessage = nil
        self.autoplayErrorMessage = nil

        self.currentStepIndex = 0
        self.state = .idle
        self.autoplayTimeline = .empty

        handPianoActivityGate.reset()
        self.handGateState = HandGateState(
            isNearKeyboard: false,
            hasDownwardMotion: false,
            exactPressedNotes: [],
            confidenceBoost: 0
        )
    }

    func clearAudioError() {
        self.audioRecognitionErrorMessage = nil
        self.audioPlaybackErrorMessage = nil
    }

    func stopVirtualPianoInput() {
        virtualPianoInputController?.stop()
    }

    func clearAutoplayError() {
        self.autoplayErrorMessage = nil
    }

    func startGuidingIfReady() {
        guard self.state == .ready, self.steps.isEmpty == false else { return }

        let navigation = stepNavigator.restart(steps: self.steps, activeRange: self.activeRange)
        self.currentStepIndex = navigation.currentStepIndex
        recordPassageRestart()
        setCurrentHighlightGuideForStepIndex(self.currentStepIndex)
        self.state = navigation.state

        if self.autoplayState == .playing {
            refreshAudioRecognitionForCurrentState()
        } else {
            _ = prepareAudioRecognitionSuppressWindowForPlayback()
            refreshAudioRecognitionForCurrentState()
            playCurrentStepSound(applyRecognitionSuppress: false)
        }

        startAutoplayTaskIfNeeded()
    }

    func skip() {
        if self.state == .ready {
            startGuidingIfReady()
            return
        }

        stopManualReplayTask()
        stopAutoplayTask()
        if self.autoplayState == .playing || self.isManualReplayPlaying {
            stopAutoplayAudio()
        }

        advanceToNextManualUnit()
        startAutoplayTaskIfNeeded()
    }

    func replayCurrentUnit() {
        guard self.autoplayState == .off else { return }
        guard let plan = manualAdvanceStrategy.replayPlan(in: manualAdvanceContext) else { return }
        startManualReplay(with: plan)
    }

    func playCurrentStepSound() {
        playCurrentStepSound(applyRecognitionSuppress: true)
    }

    func playCurrentStepSound(applyRecognitionSuppress: Bool) {
        playbackControlService?.playCurrentStepSound(applyRecognitionSuppress: applyRecognitionSuppress)
    }

    func setAutoplayEnabled(_ isEnabled: Bool) {
        if isEnabled {
            stopManualReplayTask()
            stopVirtualPianoInput()
            playbackControlService?.setAutoplayEnabled(true)
        } else {
            playbackControlService?.setAutoplayEnabled(false)
        }
        refreshAudioRecognitionForCurrentState()
    }

    private func advanceToNextManualUnit() {
        guard self.steps.isEmpty == false else {
            self.state = .idle
            return
        }
        guard let nextIndex = manualAdvanceStrategy.nextStepIndex(in: manualAdvanceContext) else {
            completeManualAdvance()
            return
        }
        moveToStep(nextIndex, shouldPlaySound: self.autoplayState == .off)
    }

    func advanceToNextStep() {
        let navigation = stepNavigator.advance(
            steps: self.steps,
            currentStepIndex: self.currentStepIndex,
            activeRange: self.activeRange
        )
        guard case let .guiding(stepIndex: nextIndex) = navigation.state else {
            if navigation.state == .idle {
                self.state = .idle
                return
            }

            recordPassageCompletion()
            if activeRoundConfiguration?.loopEnabled == true,
               let firstStepIndex = activeRange?.firstStepIndex
            {
                moveToStep(firstStepIndex, shouldPlaySound: autoplayState == .off)
                return
            }

            self.currentStepIndex = navigation.currentStepIndex
            self.currentHighlightGuideIndex = nil
            self.pressedNotes.removeAll()
            self.state = navigation.state
            stopAutoplayTask()
            stopAutoplayAudio()
            stopAudioRecognition()
            return
        }

        chordAttemptAccumulator.reset()
        let previousTick = self.steps.indices.contains(self.currentStepIndex) ? self.steps[self.currentStepIndex].tick : 0
        self.currentStepIndex = navigation.currentStepIndex
        self.state = navigation.state
        updateHighlightGuideAfterStepAdvance(previousTick: previousTick, nextStepIndex: nextIndex)

        if self.autoplayState == .playing {
            refreshAudioRecognitionForCurrentState()
        } else {
            _ = prepareAudioRecognitionSuppressWindowForPlayback()
            refreshAudioRecognitionForCurrentState()
            playCurrentStepSound(applyRecognitionSuppress: false)
        }
    }

    func moveToStep(_ nextStepIndex: Int, shouldPlaySound: Bool) {
        let navigation = stepNavigator.move(
            to: nextStepIndex,
            steps: self.steps,
            activeRange: self.activeRange
        )
        guard case let .guiding(stepIndex: targetIndex) = navigation.state else {
            completeManualAdvance()
            return
        }
        let previousTick = self.steps.indices.contains(self.currentStepIndex) ? self.steps[self.currentStepIndex].tick : self.steps[nextStepIndex].tick

        chordAttemptAccumulator.reset()
        self.currentStepIndex = navigation.currentStepIndex
        self.state = navigation.state
        updateHighlightGuideAfterStepAdvance(previousTick: previousTick, nextStepIndex: targetIndex)
        refreshAudioRecognitionForCurrentState()

        if shouldPlaySound {
            _ = prepareAudioRecognitionSuppressWindowForPlayback()
            playCurrentStepSound(applyRecognitionSuppress: false)
        }
    }

    private func completeManualAdvance() {
        recordPassageCompletion()
        if activeRoundConfiguration?.loopEnabled == true,
           let firstStepIndex = activeRange?.firstStepIndex
        {
            moveToStep(firstStepIndex, shouldPlaySound: autoplayState == .off)
            return
        }
        self.currentStepIndex = activeRange?.completionStepIndex ?? self.steps.count
        self.currentHighlightGuideIndex = nil
        self.pressedNotes.removeAll()
        self.state = .completed
        stopManualReplayTask()
        stopAutoplayTask()
        stopAutoplayAudio()
        stopAudioRecognition()
    }

    func uniqueMIDINotes(in step: PracticeStep) -> [Int] {
        Set(step.notes.map(\.midiNote)).sorted()
    }
}
