import Foundation

public struct PracticeRoundSessionInstallation: Equatable {
    public let activeRange: PracticeActiveRange
    public let repairedProgress: SongPracticeProgress?

    public init(activeRange: PracticeActiveRange, repairedProgress: SongPracticeProgress?) {
        self.activeRange = activeRange
        self.repairedProgress = repairedProgress
    }
}

public enum PracticeRoundSessionAdvance: Equatable {
    case guiding(currentStepIndex: Int, expectedNotes: [PracticeStepNote])
    case completed(waitingForAssessment: Bool)
}

@MainActor
public final class PracticeRoundSessionController {
    private struct PendingPassageCompletion {
        let id: UUID
        let identity: PracticeSongIdentity
        let configuration: PracticeRoundConfiguration
        let fact: PracticeSessionFact
        let previousProgress: SongPracticeProgress?
    }

    public let state: PracticeSessionRuntimeState
    public let roundConfigurationController: PracticeRoundConfigurationController

    private let stepNavigator = PracticeStepNavigator()
    private let attemptReducer = PracticeAttemptReducer()
    private let coachingDecisionService: CoachingDecisionService
    private let feedbackPolicy = PracticeFeedbackPolicy()
    private var attemptReductionState = PracticeAttemptReductionState()
    private var appliedAssessmentIDs: Set<PracticeProgressAssessmentID> = []
    private var pendingPassageCompletion: PendingPassageCompletion?

    public init(
        state: PracticeSessionRuntimeState = PracticeSessionRuntimeState(),
        settingsProvider: any PracticeSessionSettingsProviderProtocol,
        defaultsStore: any PracticeRoundDefaultsStoreProtocol,
        coachingDecisionService: CoachingDecisionService = CoachingDecisionService()
    ) {
        self.state = state
        self.coachingDecisionService = coachingDecisionService
        roundConfigurationController = PracticeRoundConfigurationController(
            stateStore: state,
            settingsProvider: settingsProvider,
            defaultsStore: defaultsStore
        )
    }

    public var preparedPractice: PreparedPractice? {
        preparedPracticeStorage
    }

    private var preparedPracticeStorage: PreparedPractice?

    public var configuration: PracticeRoundConfiguration? {
        state.activeRoundConfiguration
    }

    public var currentStep: PracticeStep? {
        guard let activeRange = state.activeRange,
              activeRange.contains(stepIndex: state.currentStepIndex),
              state.steps.indices.contains(state.currentStepIndex)
        else { return nil }
        return state.steps[state.currentStepIndex]
    }

    public func install(
        preparedPractice: PreparedPractice,
        restoredProgress: SongPracticeProgress?
    ) throws -> PracticeRoundSessionInstallation {
        let measureIndex = PracticeMeasureIndex(
            steps: preparedPractice.steps,
            measureSpans: preparedPractice.measureSpans
        )
        guard let first = measureIndex.measureSpans.first?.occurrenceID,
              let last = measureIndex.measureSpans.last?.occurrenceID,
              let passage = PracticePassage(start: first, end: last)
        else {
            throw PracticePreparationError.missingMeasureStructure
        }

        roundConfigurationController.installFreshFullScoreConfiguration(passage: passage)
        guard let freshConfiguration = configuration else {
            throw PracticePreparationError.unexpected(stage: "practice.round", reason: "missing configuration")
        }

        var activeRange = try measureIndex.resolve(freshConfiguration.passage)
        var effectiveProgress = restoredProgress
        var repairedProgress: SongPracticeProgress?
        if let restoredProgress {
            let restoration = PracticeExactProgressRestorer.restore(
                restoredProgress,
                freshConfiguration: freshConfiguration,
                measureIndex: measureIndex
            )
            effectiveProgress = restoration.progress
            if let restoredConfiguration = restoration.progress.activeConfiguration {
                roundConfigurationController.restoreActiveConfiguration(restoredConfiguration)
            }
            if let restoredRange = restoration.activeRange {
                activeRange = restoredRange
            }
            if restoration.didRepairSavedState {
                repairedProgress = restoration.progress
            }
        }

        preparedPracticeStorage = preparedPractice
        state.songIdentity = preparedPractice.identity
        state.performancePlan = preparedPractice.performancePlan
        state.notationProjection = preparedPractice.notationProjection
        state.attributeTimeline = preparedPractice.attributeTimeline
        state.steps = preparedPractice.steps
        state.measureSpans = preparedPractice.measureSpans
        state.measureIndex = measureIndex
        state.activeRange = activeRange
        state.activeRangeDiagnostic = nil
        state.sessionProgress = effectiveProgress
        attemptReductionState = PracticeAttemptReductionState()
        appliedAssessmentIDs = []
        pendingPassageCompletion = nil
        state.currentStepIndex = effectiveProgress?.resumePoint?.stepIndex ?? activeRange.firstStepIndex
        state.lastAttempt = nil
        state.latestFeedbackEvent = nil
        state.currentCoachingDecision = nil
        state.feedbackEventSequence = 0
        state.state = preparedPractice.steps.isEmpty ? .idle : .ready
        state.isRestoredSessionPaused = effectiveProgress?.resumePoint != nil

        return PracticeRoundSessionInstallation(
            activeRange: activeRange,
            repairedProgress: repairedProgress
        )
    }

    public func applyPendingConfiguration() throws -> PracticeActiveRange {
        guard let preparedPractice = preparedPracticeStorage,
              let measureIndex = state.measureIndex
        else { throw PracticePreparationError.unexpected(stage: "practice.round", reason: "missing preparation") }

        _ = roundConfigurationController.applyPending()
        guard let configuration else {
            throw PracticePreparationError.unexpected(stage: "practice.round", reason: "missing configuration")
        }
        let activeRange = try measureIndex.resolve(configuration.passage)
        let restart = attemptReducer.reducePassageRestart(
            progress: state.sessionProgress,
            identity: preparedPractice.identity,
            configuration: configuration,
            timestamp: .now
        )
        var progress = restart.progress
        progress.resumePoint = nil
        state.activeRange = activeRange
        state.sessionProgress = progress
        attemptReductionState = restart.reductionState
        state.currentStepIndex = activeRange.firstStepIndex
        state.lastAttempt = nil
        state.latestFeedbackEvent = nil
        state.currentCoachingDecision = nil
        pendingPassageCompletion = nil
        state.state = .ready
        return activeRange
    }

    public func recordAttempt(_ outcome: StepAttemptMatchResult) {
        guard let preparedPractice = preparedPracticeStorage,
              let configuration,
              let measureIndex = state.measureIndex
        else { return }
        let previousProgress = state.sessionProgress
        state.lastAttempt = outcome
        let result = attemptReducer.reduceAttempt(
            progress: state.sessionProgress,
            reductionState: attemptReductionState,
            outcome: outcome,
            stepIndex: state.currentStepIndex,
            identity: preparedPractice.identity,
            configuration: configuration,
            measureIndex: measureIndex,
            timestamp: .now
        )
        state.sessionProgress = result.progress
        attemptReductionState = result.reductionState
        publishFeedback(
            for: result.fact,
            previousProgress: previousProgress,
            progress: result.progress
        )
    }

    public func advance() -> PracticeRoundSessionAdvance {
        guard let preparedPractice = preparedPracticeStorage,
              let configuration,
              let activeRange = state.activeRange
        else { return .completed(waitingForAssessment: false) }
        let navigation = stepNavigator.advance(
            steps: preparedPractice.steps,
            currentStepIndex: state.currentStepIndex,
            activeRange: activeRange
        )
        state.currentStepIndex = navigation.currentStepIndex

        switch navigation.state {
        case .guiding:
            updateResumePoint()
            return .guiding(
                currentStepIndex: state.currentStepIndex,
                expectedNotes: expectedNotesForCurrentStep()
            )
        case .completed:
            recordPassageCompletion(configuration: configuration, identity: preparedPractice.identity)
            state.state = .completed
            return .completed(waitingForAssessment: true)
        case .idle, .ready:
            return .completed(waitingForAssessment: false)
        }
    }

    public func completePassageAnalysis(
        assessment: PassagePerformanceAssessment?,
        analyzerRoundGeneration: UInt64,
        timestamp: Date = .now
    ) async -> PracticeRoundSessionAdvance {
        guard let pendingPassageCompletion,
              state.state == .completed,
              state.songIdentity == pendingPassageCompletion.identity,
              configuration == pendingPassageCompletion.configuration
        else {
            return .completed(waitingForAssessment: false)
        }

        if let assessment,
           assessment.planID == preparedPracticeStorage?.performancePlan.id
        {
            let assessmentID = PracticeProgressAssessmentID(
                analyzerRoundGeneration: analyzerRoundGeneration,
                planID: assessment.planID,
                sourceGeneration: assessment.sourceGeneration
            )
            if appliedAssessmentIDs.insert(assessmentID).inserted,
               let progress = state.sessionProgress
            {
                let decision = await coachingDecisionService.decision(
                    for: assessment,
                    scoreEvents: preparedPracticeStorage?.performancePlan.noteEvents ?? []
                )
                guard self.pendingPassageCompletion?.id == pendingPassageCompletion.id,
                      state.state == .completed,
                      state.songIdentity == pendingPassageCompletion.identity,
                      configuration == pendingPassageCompletion.configuration
                else {
                    return .completed(waitingForAssessment: false)
                }
                state.currentCoachingDecision = decision
                state.sessionProgress = attemptReducer.reducePerformanceAssessment(
                    progress: progress,
                    identity: pendingPassageCompletion.identity,
                    configuration: pendingPassageCompletion.configuration,
                    timestamp: timestamp,
                    assessment: assessment
                )
            }
        }

        guard self.pendingPassageCompletion?.id == pendingPassageCompletion.id,
              let progress = state.sessionProgress
        else {
            return .completed(waitingForAssessment: false)
        }
        publishFeedback(
            for: pendingPassageCompletion.fact,
            previousProgress: pendingPassageCompletion.previousProgress,
            progress: progress
        )
        self.pendingPassageCompletion = nil

        guard pendingPassageCompletion.configuration.loopEnabled,
              let preparedPractice = preparedPracticeStorage,
              let activeRange = state.activeRange
        else {
            return .completed(waitingForAssessment: false)
        }
        beginNextLoopRound(
            preparedPractice: preparedPractice,
            configuration: pendingPassageCompletion.configuration,
            activeRange: activeRange
        )
        return .guiding(
            currentStepIndex: state.currentStepIndex,
            expectedNotes: expectedNotesForCurrentStep()
        )
    }

    public func stageCurrentCoachingRound() -> Bool {
        guard let decision = state.currentCoachingDecision,
              let passage = coachingPassage(for: decision)
        else { return false }
        roundConfigurationController.pendingPassage = passage
        if let tempoScale = decision.action.tempoRatio {
            roundConfigurationController.pendingTempoScale = tempoScale
        }
        return true
    }

    public func acceptCurrentCoachingDecision() async {
        guard let decision = state.currentCoachingDecision else { return }
        await acceptCoachingDecision(decision)
        state.currentCoachingDecision = nil
    }

    public func acceptCoachingDecision(_ decision: CoachingDecision) async {
        await coachingDecisionService.accept(decision)
    }

    public func skipCurrentCoachingDecision() async {
        guard let decision = state.currentCoachingDecision else { return }
        await coachingDecisionService.skip(decision)
        state.currentCoachingDecision = nil
    }

    public func expectedNotesForCurrentStep() -> [PracticeStepNote] {
        guard let configuration, let currentStep else { return [] }
        guard configuration.handMode != .both else { return currentStep.notes }
        return currentStep.notes.filter { configuration.handMode.allows(hand: $0.hand) }
    }

    public func reset() {
        roundConfigurationController.resetSong()
        preparedPracticeStorage = nil
        attemptReductionState = PracticeAttemptReductionState()
        appliedAssessmentIDs = []
        pendingPassageCompletion = nil
        state.state = .idle
        state.sessionProgress = nil
        state.latestFeedbackEvent = nil
        state.currentCoachingDecision = nil
        state.feedbackEventSequence = 0
        state.songIdentity = nil
        state.progressGeneration = nil
        state.isRestoredSessionPaused = false
        state.acceptsPracticeAttempts = true
        state.measureIndex = nil
        state.activeRange = nil
        state.activeRangeDiagnostic = nil
        state.performancePlan = nil
        state.notationProjection = nil
        state.steps = []
        state.currentStepIndex = 0
        state.autoplayState = .off
        state.isSustainPedalDown = false
        state.playbackErrorMessage = nil
        state.autoplayErrorMessage = nil
        state.measureSpans = []
        state.manualReplayGeneration &+= 1
        state.isManualReplayPlaying = false
        state.attributeTimeline = nil
        state.autoplayTimeline = .empty
        state.isPracticeInputRunning = false
        state.lastAttempt = nil
    }

    private func updateResumePoint() {
        guard let measureIndex = state.measureIndex,
              let occurrenceID = measureIndex.occurrenceID(forStepIndex: state.currentStepIndex),
              var progress = state.sessionProgress
        else { return }
        progress.resumePoint = PracticeResumePoint(
            occurrenceID: occurrenceID,
            stepIndex: state.currentStepIndex,
            updatedAt: .now
        )
        progress.updatedAt = .now
        state.sessionProgress = progress
    }

    private func recordPassageCompletion(
        configuration: PracticeRoundConfiguration,
        identity: PracticeSongIdentity
    ) {
        let previousProgress = state.sessionProgress
        let result = attemptReducer.reducePassageCompletion(
            progress: state.sessionProgress,
            reductionState: attemptReductionState,
            identity: identity,
            configuration: configuration,
            timestamp: .now
        )
        state.sessionProgress = result.progress
        attemptReductionState = result.reductionState
        if let fact = result.fact {
            pendingPassageCompletion = PendingPassageCompletion(
                id: UUID(),
                identity: identity,
                configuration: configuration,
                fact: fact,
                previousProgress: previousProgress
            )
        }
    }

    private func beginNextLoopRound(
        preparedPractice: PreparedPractice,
        configuration: PracticeRoundConfiguration,
        activeRange: PracticeActiveRange
    ) {
        roundConfigurationController.beginNextRound()
        let restart = attemptReducer.reducePassageRestart(
            progress: state.sessionProgress,
            identity: preparedPractice.identity,
            configuration: configuration,
            timestamp: .now
        )
        state.sessionProgress = restart.progress
        attemptReductionState = restart.reductionState
        state.currentStepIndex = activeRange.firstStepIndex
        updateResumePoint()
        state.lastAttempt = nil
        state.latestFeedbackEvent = nil
        state.currentCoachingDecision = nil
    }

    private func publishFeedback(
        for fact: PracticeSessionFact?,
        previousProgress: SongPracticeProgress?,
        progress: SongPracticeProgress
    ) {
        let nextSequence = state.feedbackEventSequence + 1
        let events = feedbackPolicy.events(
            for: fact,
            previousProgress: previousProgress,
            progress: progress,
            eventSequence: nextSequence,
            passageSourceMeasureIDs: state.activeRange?.sourceMeasureIDs ?? [],
            coachingDecision: state.currentCoachingDecision
        )
        guard events.isEmpty == false else { return }
        state.feedbackEventSequence = nextSequence
        state.latestFeedbackEvent = events.last
    }

    private func coachingPassage(for decision: CoachingDecision) -> PracticePassage? {
        let occurrenceIDs = Set(decision.issue.measureOccurrenceIDs)
        let localizedSpans = state.measureSpans.filter { occurrenceIDs.contains($0.occurrenceID) }
        let matchingSpans = localizedSpans.isEmpty ? state.measureSpans.filter { span in
            span.startTick < decision.action.scoreRange.upperBound
                && decision.action.scoreRange.lowerBound < span.endTick
        } : localizedSpans
        guard let first = matchingSpans.first else { return nil }
        let samePartSpans = matchingSpans.filter { $0.partID == first.partID }
        guard let last = samePartSpans.last else { return nil }
        return PracticePassage(start: first.occurrenceID, end: last.occurrenceID)
    }
}
