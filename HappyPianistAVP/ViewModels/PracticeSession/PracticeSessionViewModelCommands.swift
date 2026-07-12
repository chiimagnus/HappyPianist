import Foundation

extension PracticeSessionViewModel {
    var audioErrorMessage: String? {
        self.audioRecognitionErrorMessage ?? self.audioPlaybackErrorMessage
    }

    var currentStep: PracticeStep? {
        guard self.stateStore.isActiveRangeInvalid == false else { return nil }
        guard self.state != .completed else { return nil }
        guard self.steps.indices.contains(self.currentStepIndex) else { return nil }
        guard self.activeRange?.contains(stepIndex: self.currentStepIndex) ?? true else { return nil }
        return self.steps[self.currentStepIndex]
    }

    var currentPianoHighlightGuide: PianoHighlightGuide? {
        guard self.stateStore.isActiveRangeInvalid == false else { return nil }
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
        guard self.stateStore.isActiveRangeInvalid == false else { return [] }
        return self.activeRange?.measureSpans ?? self.measureSpans
    }

    var activeHighlightGuides: [PianoHighlightGuide] {
        guard self.stateStore.isActiveRangeInvalid == false else { return [] }
        guard let activeRange = self.activeRange else { return self.highlightGuides }
        return self.highlightGuides.filter { activeRange.contains(tick: $0.tick) }
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

    func restoreProgressIfAvailable() async {
        guard let identity = self.songIdentity, let progressCoordinator else { return }
        let session = await progressCoordinator.begin(identity: identity)
        guard session.isCurrent, self.songIdentity == identity else { return }
        self.progressGeneration = session.generation
        self.progressSaveStatus = .loaded
        self.acceptsPracticeAttempts = true

        guard let progress = session.progress else {
            self.isRestoredSessionPaused = false
            return
        }

        self.sessionProgress = progress
        if let configuration = progress.activeConfiguration {
            roundConfigurationController.restoreActiveConfiguration(configuration)
            rebuildActiveRange()
        }
        if let resumePoint = progress.resumePoint,
           self.measureIndex?.occurrenceID(forStepIndex: resumePoint.stepIndex) == resumePoint.occurrenceID,
           self.activeRange?.contains(stepIndex: resumePoint.stepIndex) ?? true
        {
            self.currentStepIndex = resumePoint.stepIndex
        } else {
            self.currentStepIndex = self.activeRange?.firstStepIndex ?? 0
        }
        setCurrentHighlightGuideForStepIndex(self.currentStepIndex)
        self.state = self.steps.isEmpty ? .idle : .ready
        self.isRestoredSessionPaused = self.steps.isEmpty == false
        refreshAudioRecognitionForCurrentState()
        refreshPracticeInputForCurrentState()
    }

    func checkpointProgress() {
        guard let progressCoordinator,
              let generation = self.progressGeneration,
              let progress = self.sessionProgress
        else { return }
        self.progressSaveStatus = .pending
        Task {
            await progressCoordinator.checkpoint(progress, generation: generation)
        }
    }

    func flushProgress() async {
        guard let progressCoordinator, let generation = self.progressGeneration else { return }
        if let progress = self.sessionProgress {
            await progressCoordinator.checkpoint(progress, generation: generation)
        }
        self.progressSaveStatus = await progressCoordinator.flush(generation: generation)
    }

    func suspendAndFlushProgress() async {
        self.acceptsPracticeAttempts = false
        stopManualReplayTask()
        stopAutoplayTask()
        stopAutoplayAudio()
        stopAudioRecognition()
        stopPracticeInput()
        await flushProgress()
    }

    func resumeAfterSuspension() {
        guard self.hasShutdown == false, self.steps.isEmpty == false, self.state != .completed else { return }
        self.acceptsPracticeAttempts = true
        self.isRestoredSessionPaused = true
        self.state = .ready
        setCurrentHighlightGuideForStepIndex(self.currentStepIndex)
        refreshAudioRecognitionForCurrentState()
    }

    func flushAndShutdown() async {
        await suspendAndFlushProgress()
        if let progressCoordinator, let generation = self.progressGeneration {
            self.progressSaveStatus = await progressCoordinator.finish(generation: generation)
        }
        shutdown()
    }

    func recordAttemptOutcome(_ outcome: StepAttemptMatchResult, at timestamp: Date = .now) {
        self.lastAttemptOutcome = outcome
        guard self.stateStore.isActiveRangeInvalid == false else { return }
        guard let identity = self.songIdentity,
              let configuration = self.activeRoundConfiguration,
              let measureIndex = self.measureIndex
        else {
            return
        }

        let previousProgress = self.sessionProgress
        let result = attemptReducer.reduceAttempt(
            progress: self.sessionProgress,
            reductionState: self.attemptReductionState,
            outcome: outcome,
            stepIndex: self.currentStepIndex,
            identity: identity,
            configuration: configuration,
            roundGeneration: self.roundGeneration,
            measureIndex: measureIndex,
            timestamp: timestamp
        )
        self.sessionProgress = result.progress
        self.attemptReductionState = result.reductionState
        self.lastSessionFact = result.fact
        publishFeedback(for: result.fact, previousProgress: previousProgress, progress: result.progress)
        if result.fact != nil {
            checkpointProgress()
        }
    }

    func recordPassageRestart(at timestamp: Date = .now) {
        guard let identity = self.songIdentity, let configuration = self.activeRoundConfiguration else { return }
        let result = attemptReducer.reducePassageRestart(
            progress: self.sessionProgress,
            identity: identity,
            configuration: configuration,
            roundGeneration: self.roundGeneration,
            timestamp: timestamp
        )
        self.sessionProgress = result.progress
        self.attemptReductionState = result.reductionState
        self.lastSessionFact = result.fact
        checkpointProgress()
    }

    func recordPassageCompletion(at timestamp: Date = .now) {
        guard let identity = self.songIdentity, let configuration = self.activeRoundConfiguration else { return }
        let previousProgress = self.sessionProgress
        let result = attemptReducer.reducePassageCompletion(
            progress: self.sessionProgress,
            reductionState: self.attemptReductionState,
            identity: identity,
            configuration: configuration,
            roundGeneration: self.roundGeneration,
            timestamp: timestamp
        )
        self.sessionProgress = result.progress
        self.attemptReductionState = result.reductionState
        self.lastSessionFact = result.fact
        publishFeedback(for: result.fact, previousProgress: previousProgress, progress: result.progress)
        checkpointProgress()
    }

    private func publishFeedback(
        for fact: PracticeSessionFact?,
        previousProgress: SongPracticeProgress?,
        progress: SongPracticeProgress
    ) {
        let nextSequence = self.feedbackEventSequence + 1
        let events = feedbackPolicy.events(
            for: fact,
            previousProgress: previousProgress,
            progress: progress,
            sessionGeneration: self.progressGeneration ?? 0,
            eventSequence: nextSequence,
            passageSourceMeasureIDs: self.activeRange?.sourceMeasureIDs ?? []
        )
        guard events.isEmpty == false else { return }
        self.feedbackEventSequence = nextSequence
        for event in events where event.roundGeneration == self.roundGeneration && event.identity == self.songIdentity {
            self.latestFeedbackEvent = event
        }
    }

    @discardableResult
    func applyPendingRoundConfiguration() -> Bool {
        stopManualReplayTask()
        stopAutoplayTask()
        stopAutoplayAudio()
        stopAudioRecognition()
        let routingChanged = roundConfigurationController.applyPending()
        rebuildActiveRange()
        self.currentStepIndex = self.activeRange?.firstStepIndex ?? 0
        self.state = self.steps.isEmpty ? .idle : .ready
        self.isRestoredSessionPaused = false
        self.acceptsPracticeAttempts = true
        self.latestFeedbackEvent = nil
        recordPassageRestart()
        setCurrentHighlightGuideForStepIndex(self.currentStepIndex)
        rebuildAutoplayTimeline()
        refreshAudioRecognitionForCurrentState()
        refreshPracticeInputForCurrentState()
        return routingChanged
    }

    func rebuildActiveRange() {
        guard let configuration = self.activeRoundConfiguration, let measureIndex = self.measureIndex else {
            self.activeRange = nil
            self.activeRangeDiagnostic = nil
            return
        }
        do {
            self.activeRange = try measureIndex.resolve(configuration.passage)
            self.activeRangeDiagnostic = nil
        } catch let diagnostic as PracticeMeasureIndexDiagnostic {
            self.activeRange = nil
            self.activeRangeDiagnostic = diagnostic
        } catch {
            self.activeRange = nil
            self.activeRangeDiagnostic = .passageBoundaryNotFound
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
           let lastMeasure = measureSpans.prefix(4).last,
           let passage = PracticePassage(start: firstMeasure.occurrenceID, end: lastMeasure.occurrenceID)
        {
            roundConfigurationController.installInitialPassageIfNeeded(passage)
        }
        self.measureIndex = PracticeMeasureIndex(steps: steps, measureSpans: measureSpans)
        rebuildActiveRange()
        self.pedalTimeline = pedalTimeline
        self.fermataTimeline = fermataTimeline
        self.attributeTimeline = attributeTimeline
        self.slurTimeline = slurTimeline
        self.highlightGuides = highlightGuides
        rebuildAutoplayTimeline()
        self.currentHighlightGuideIndex = nil

        if shouldResetProgress {
            self.currentStepIndex = self.activeRange?.firstStepIndex ?? 0
            self.currentHighlightGuideIndex = nil
            self.pressedNotes.removeAll()
            self.attemptReductionState = PracticeAttemptReductionState()
            self.lastAttemptOutcome = nil
            self.lastSessionFact = nil
            self.latestFeedbackEvent = nil
            if self.sessionProgress?.identity != self.songIdentity {
                self.sessionProgress = nil
            }
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
        self.progressGeneration = nil
        self.progressSaveStatus = .idle
        self.isRestoredSessionPaused = false
        self.acceptsPracticeAttempts = true
        self.sessionProgress = nil
        self.latestFeedbackEvent = nil
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
        guard self.stateStore.isActiveRangeInvalid == false else { return }
        guard self.state == .ready, self.steps.isEmpty == false else { return }

        if self.isRestoredSessionPaused {
            self.isRestoredSessionPaused = false
            self.acceptsPracticeAttempts = true
            setCurrentHighlightGuideForStepIndex(self.currentStepIndex)
            self.state = .guiding(stepIndex: self.currentStepIndex)
        } else {
            let navigation = stepNavigator.restart(steps: self.steps, activeRange: self.activeRange)
            self.currentStepIndex = navigation.currentStepIndex
            recordPassageRestart()
            setCurrentHighlightGuideForStepIndex(self.currentStepIndex)
            self.state = navigation.state
        }

        if self.autoplayState == .playing {
            refreshAudioRecognitionForCurrentState()
        } else {
            _ = prepareAudioRecognitionSuppressWindowForPlayback()
            refreshAudioRecognitionForCurrentState()
            playCurrentStepSound(applyRecognitionSuppress: false)
        }

        startAutoplayTaskIfNeeded()
    }

    func prepareStartOver(at timestamp: Date = .now) {
        stopManualReplayTask()
        stopAutoplayTask()
        stopAutoplayAudio()
        stopAudioRecognition()
        if let firstMeasure = self.measureSpans.first,
           let lastMeasure = self.measureSpans.last,
           let fullPassage = PracticePassage(
               start: firstMeasure.occurrenceID,
               end: lastMeasure.occurrenceID
           )
        {
            roundConfigurationController.pendingPassage = fullPassage
            _ = roundConfigurationController.applyPending()
            rebuildActiveRange()
        }
        self.acceptsPracticeAttempts = true
        self.isRestoredSessionPaused = false
        self.currentStepIndex = self.activeRange?.firstStepIndex ?? 0
        self.state = self.steps.isEmpty ? .idle : .ready
        setCurrentHighlightGuideForStepIndex(self.currentStepIndex)
        if let occurrenceID = self.measureIndex?.occurrenceID(forStepIndex: self.currentStepIndex),
           var progress = self.sessionProgress
        {
            progress.resumePoint = PracticeResumePoint(
                occurrenceID: occurrenceID,
                stepIndex: self.currentStepIndex,
                updatedAt: timestamp
            )
            progress.updatedAt = timestamp
            self.sessionProgress = progress
        }
        recordPassageRestart(at: timestamp)
    }

    func retryMeasure(_ sourceMeasureID: PracticeSourceMeasureID) {
        let span = self.activeRange?.measureSpans.first(where: {
            $0.occurrenceID.sourceMeasureID == sourceMeasureID
        }) ?? self.measureSpans.first(where: {
            $0.occurrenceID.sourceMeasureID == sourceMeasureID
        })
        guard let span,
              let passage = PracticePassage(start: span.occurrenceID, end: span.occurrenceID)
        else { return }
        roundConfigurationController.pendingPassage = passage
        _ = applyPendingRoundConfiguration()
        startGuidingIfReady()
    }

    @discardableResult
    func perform(_ action: PracticeNextAction) -> Bool {
        switch action {
        case let .retryMeasure(id):
            retryMeasure(id)
        case let .lowerTempo(scale):
            roundConfigurationController.pendingTempoScale = scale
            _ = applyPendingRoundConfiguration()
            startGuidingIfReady()
        case .keepTempo:
            _ = applyPendingRoundConfiguration()
            startGuidingIfReady()
        case .expandPassage:
            guard let activeRange = self.activeRange,
                  let first = self.measureSpans.firstIndex(where: { $0.occurrenceID == activeRange.measureSpans.first?.occurrenceID }),
                  let last = self.measureSpans.firstIndex(where: { $0.occurrenceID == activeRange.measureSpans.last?.occurrenceID }),
                  let passage = PracticePassage(
                      start: self.measureSpans[max(0, first - 1)].occurrenceID,
                      end: self.measureSpans[min(self.measureSpans.count - 1, last + 1)].occurrenceID
                  )
            else { return false }
            roundConfigurationController.pendingPassage = passage
            _ = applyPendingRoundConfiguration()
            startGuidingIfReady()
        case .continuePassage:
            _ = applyPendingRoundConfiguration()
            startGuidingIfReady()
        }
        return true
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
        guard self.stateStore.isActiveRangeInvalid == false else { return }
        guard self.autoplayState == .off else { return }
        guard let plan = manualAdvanceStrategy.replayPlan(in: manualAdvanceContext) else { return }
        startManualReplay(with: plan)
    }

    func playCurrentStepSound() {
        guard self.stateStore.isActiveRangeInvalid == false else { return }
        playCurrentStepSound(applyRecognitionSuppress: true)
    }

    func playCurrentStepSound(applyRecognitionSuppress: Bool) {
        playbackControlService?.playCurrentStepSound(applyRecognitionSuppress: applyRecognitionSuppress)
    }

    func setAutoplayEnabled(_ isEnabled: Bool) {
        guard isEnabled == false || self.stateStore.isActiveRangeInvalid == false else { return }
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
            if self.activeRoundConfiguration?.loopEnabled == true,
               self.isActivePassageStable == false,
               let firstStepIndex = self.activeRange?.firstStepIndex
            {
                beginNextLoopRound(at: firstStepIndex)
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
        updateResumePointAfterNavigation()
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
        updateResumePointAfterNavigation()
        updateHighlightGuideAfterStepAdvance(previousTick: previousTick, nextStepIndex: targetIndex)
        refreshAudioRecognitionForCurrentState()

        if shouldPlaySound {
            _ = prepareAudioRecognitionSuppressWindowForPlayback()
            playCurrentStepSound(applyRecognitionSuppress: false)
        }
    }

    private func updateResumePointAfterNavigation(at timestamp: Date = .now) {
        guard let occurrenceID = self.measureIndex?.occurrenceID(forStepIndex: self.currentStepIndex),
              var progress = self.sessionProgress
        else { return }
        progress.resumePoint = PracticeResumePoint(
            occurrenceID: occurrenceID,
            stepIndex: self.currentStepIndex,
            updatedAt: timestamp
        )
        progress.updatedAt = timestamp
        self.sessionProgress = progress
        checkpointProgress()
    }

    private func completeManualAdvance() {
        recordPassageCompletion()
        if self.activeRoundConfiguration?.loopEnabled == true,
           self.isActivePassageStable == false,
           let firstStepIndex = self.activeRange?.firstStepIndex
        {
            beginNextLoopRound(at: firstStepIndex)
            return
        }
        self.currentStepIndex = self.activeRange?.completionStepIndex ?? self.steps.count
        self.currentHighlightGuideIndex = nil
        self.pressedNotes.removeAll()
        self.state = .completed
        stopManualReplayTask()
        stopAutoplayTask()
        stopAutoplayAudio()
        stopAudioRecognition()
    }

    private func beginNextLoopRound(at firstStepIndex: Int) {
        roundConfigurationController.beginNextRound()
        self.latestFeedbackEvent = nil
        recordPassageRestart()
        moveToStep(firstStepIndex, shouldPlaySound: self.autoplayState == .off)
    }

    private var isActivePassageStable: Bool {
        guard let configuration = self.activeRoundConfiguration,
              let progress = self.sessionProgress
        else { return false }
        let facts = progress.measureFacts.filter { $0.handMode == configuration.handMode }
        return PracticePassageCoverage.isStable(
            facts: facts,
            sourceMeasureIDs: self.activeRange?.sourceMeasureIDs ?? []
        )
    }

    func uniqueMIDINotes(in step: PracticeStep) -> [Int] {
        Set(step.notes.map(\.midiNote)).sorted()
    }
}
