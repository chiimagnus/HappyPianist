import Diagnostics
import Foundation
import Library
import MIDI
import MusicXML
import Observation
import Practice

enum MacPracticeState: Equatable {
    case idle
    case preparing
    case guiding
    case completed
    case inputUnavailable
    case preparationFailed
    case progressRecoveryRequired
    case saveFailed
}

@MainActor
@Observable
final class MacPracticeViewModel {
    private let resolveEntry: @Sendable (UUID) async -> Result<ResolvedSongLibraryEntry, SongLibraryEntryResolutionError>
    private let preparationService: any PracticePreparationServiceProtocol
    private let progressRepository: any PracticeProgressRepositoryProtocol
    private let progressRecovery: (any PracticeProgressRecoveryProtocol)?
    private let sessionRecorder: PracticeSessionRecorder
    private let midiSettingsViewModel: MIDISettingsViewModel
    private let makeReferencePlaybackService: (Int32) -> any PracticeSequencerPlaybackServiceProtocol
    private let diagnosticsReporter: (any DiagnosticsReporting)?
    private let sessionController: PracticeRoundSessionController
    private let playbackSequenceBuilder = PlaybackSequenceBuilder()

    let roundConfigurationController: PracticeRoundConfigurationController
    let takeLibraryViewModel: TakeLibraryViewModel
    let takePlaybackViewModel: TakePlaybackViewModel

    private var midiSession: MIDIPracticeSession?
    private var referencePlaybackService: (any PracticeSequencerPlaybackServiceProtocol)?
    private var takeRecorder = RecordingTakeRecorder()
    private var pendingTake: RecordingTake?
    private var takePlaybackOutputEndpointID: Int32?
    @ObservationIgnored private var manualReplayTask: Task<Void, Never>?
    @ObservationIgnored private var passageAnalysisTask: Task<Void, Never>?
    private var loadedSongID: UUID?
    private var loadGeneration = 0
    private var inputGeneration = 0
    private var passageAnalysisGeneration = 0

    private(set) var state: MacPracticeState = .idle
    private(set) var errorMessage: String?
    private(set) var isRecordingTake = false
    private(set) var recordingTakeStartedAt: Date?

    var preparedPractice: PreparedPractice? {
        sessionController.preparedPractice
    }

    private var activeRange: PracticeActiveRange? {
        get { sessionController.state.activeRange }
        set { sessionController.state.activeRange = newValue }
    }

    private var progress: SongPracticeProgress? {
        get { sessionController.state.sessionProgress }
        set { sessionController.state.sessionProgress = newValue }
    }

    private(set) var currentStepIndex: Int {
        get { sessionController.state.currentStepIndex }
        set { sessionController.state.currentStepIndex = newValue }
    }

    var lastAttempt: StepAttemptMatchResult? {
        sessionController.state.lastAttempt
    }

    var latestFeedbackEvent: PracticeFeedbackEvent? {
        sessionController.state.latestFeedbackEvent
    }

    var currentCoachingDecision: CoachingDecision? {
        sessionController.state.currentCoachingDecision
    }

    var canReplayActiveRange: Bool {
        state == .guiding &&
            referencePlaybackService != nil &&
            midiSettingsViewModel.selectedAvailableOutputEndpointID != nil &&
            preparedPractice != nil &&
            activeRange != nil
    }

    var canPlayTakes: Bool {
        midiSettingsViewModel.selectedAvailableOutputEndpointID != nil
    }

    var canToggleTakeRecording: Bool {
        state == .guiding && (isRecordingTake || sessionController.state.isManualReplayPlaying == false)
    }

    init(
        resolveEntry: @escaping @Sendable (UUID) async -> Result<ResolvedSongLibraryEntry, SongLibraryEntryResolutionError>,
        preparationService: any PracticePreparationServiceProtocol,
        progressRepository: any PracticeProgressRepositoryProtocol,
        progressRecovery: (any PracticeProgressRecoveryProtocol)? = nil,
        sessionRecorder: PracticeSessionRecorder,
        midiSettingsViewModel: MIDISettingsViewModel,
        makeReferencePlaybackService: @escaping (Int32) -> any PracticeSequencerPlaybackServiceProtocol,
        settingsProvider: any PracticeSessionSettingsProviderProtocol,
        roundDefaultsStore: any PracticeRoundDefaultsStoreProtocol,
        takeLibraryViewModel: TakeLibraryViewModel = TakeLibraryViewModel(),
        takePlaybackViewModel: TakePlaybackViewModel = TakePlaybackViewModel(),
        diagnosticsReporter: (any DiagnosticsReporting)? = nil
    ) {
        self.resolveEntry = resolveEntry
        self.preparationService = preparationService
        self.progressRepository = progressRepository
        self.progressRecovery = progressRecovery
        self.sessionRecorder = sessionRecorder
        self.midiSettingsViewModel = midiSettingsViewModel
        self.makeReferencePlaybackService = makeReferencePlaybackService
        self.diagnosticsReporter = diagnosticsReporter
        self.takeLibraryViewModel = takeLibraryViewModel
        self.takePlaybackViewModel = takePlaybackViewModel
        let sessionController = PracticeRoundSessionController(
            settingsProvider: settingsProvider,
            defaultsStore: roundDefaultsStore
        )
        self.sessionController = sessionController
        roundConfigurationController = sessionController.roundConfigurationController
    }

    private var configuration: PracticeRoundConfiguration? {
        sessionController.configuration
    }

    func load(songID: UUID) async {
        guard loadedSongID != songID || preparedPractice == nil else { return }
        if state != .idle {
            guard await finishCurrentPractice() else { return }
        }
        await discardCurrentPractice()
        loadGeneration &+= 1
        let generation = loadGeneration
        loadedSongID = songID
        state = .preparing
        errorMessage = nil

        switch await progressRepository.load() {
        case .loaded:
            break
        case .corrupted:
            guard generation == loadGeneration else { return }
            state = .progressRecoveryRequired
            errorMessage = "练习进度文件需要恢复后才能开始。"
            return
        case .unavailable:
            guard generation == loadGeneration else { return }
            state = .saveFailed
            errorMessage = "暂时无法读取练习进度；请恢复后重试。"
            return
        }

        let resolved: ResolvedSongLibraryEntry
        switch await resolveEntry(songID) {
        case let .success(entry):
            resolved = entry
        case .failure:
            guard generation == loadGeneration else { return }
            state = .preparationFailed
            errorMessage = "无法读取所选曲谱。"
            return
        }

        do {
            let prepared = try await preparationService.prepare(
                songID: resolved.entry.id,
                from: resolved.scoreURL,
                file: ImportedMusicXMLFile(
                    fileName: resolved.entry.musicXMLFileName,
                    storedURL: resolved.scoreURL,
                    importedAt: resolved.entry.importedAt
                ),
                options: .practice
            )
            guard generation == loadGeneration else { return }
            let restoredProgress = await progressRepository.progress(for: prepared.identity)
            guard generation == loadGeneration else { return }
            try await install(
                prepared,
                restoredProgress: restoredProgress,
                generation: generation
            )
        } catch is CancellationError {
            return
        } catch {
            guard generation == loadGeneration else { return }
            state = .preparationFailed
            errorMessage = "无法准备此曲谱。"
        }
    }

    func recoverProgress() async {
        guard let progressRecovery else { return }
        guard let songID = loadedSongID else { return }
        do {
            _ = try await progressRecovery.recoverFromCorruption()
            await discardCurrentPractice()
            await load(songID: songID)
        } catch {
            state = .progressRecoveryRequired
            errorMessage = "练习进度恢复失败；请稍后重试。"
        }
    }

    func retryPreparation() async {
        guard let loadedSongID else { return }
        await discardCurrentPractice()
        await load(songID: loadedSongID)
    }

    func returnToLibrary() async -> Bool {
        let finished = await finishCurrentPractice()
        guard finished else { return false }
        await discardCurrentPractice()
        return true
    }

    private func install(
        _ prepared: PreparedPractice,
        restoredProgress: SongPracticeProgress?,
        generation: Int
    ) async throws {
        let installation = try sessionController.install(
            preparedPractice: prepared,
            restoredProgress: restoredProgress
        )
        if let repairedProgress = installation.repairedProgress {
            do {
                try await progressRepository.upsert(repairedProgress)
            } catch {
                guard generation == loadGeneration else { return }
                state = .saveFailed
                errorMessage = "已修复的练习状态暂时无法保存；请恢复后重试。"
                return
            }
        }

        guard generation == loadGeneration else { return }
        await start(prepared: prepared, activeRange: installation.activeRange, generation: generation)
    }

    private func start(
        prepared: PreparedPractice,
        activeRange: PracticeActiveRange,
        generation: Int
    ) async {
        await startGuidingInput(
            prepared: prepared,
            activeRange: activeRange,
            generation: generation,
            startsVisit: true
        )
    }

    private func startGuidingInput(
        prepared: PreparedPractice,
        activeRange: PracticeActiveRange,
        generation: Int,
        startsVisit: Bool
    ) async {
        guard generation == loadGeneration,
              let configuration
        else { return }
        midiSettingsViewModel.load()
        guard let input = midiSettingsViewModel.selectedInputForPractice() else {
            state = .inputUnavailable
            errorMessage = "请选择可用的 MIDI 输入后再开始练习。"
            return
        }
        if startsVisit {
            _ = await sessionRecorder.beginVisit(
                id: UUID(),
                songID: prepared.identity.songID,
                sceneIsActive: true
            )
            _ = await sessionRecorder.bindIdentity(prepared.identity)
        }
        guard generation == loadGeneration,
              self.configuration == configuration,
              self.activeRange == activeRange
        else { return }
        referencePlaybackService = midiSettingsViewModel.selectedAvailableOutputEndpointID.map(
            makeReferencePlaybackService
        )
        state = .guiding
        errorMessage = nil
        inputGeneration &+= 1
        let sessionInputGeneration = inputGeneration
        let session = MIDIPracticeSession(
            inputEventSource: input,
            diagnosticsReporter: diagnosticsReporter,
            observationRecorder: sessionRecorder,
            onObservation: { [weak self] observation in
                self?.recordTakeObservation(observation)
            },
            onEvent: { [weak self] event in
                guard let self, self.inputGeneration == sessionInputGeneration else { return }
                self.handle(event)
            }
        )
        midiSession = session
        midiSettingsViewModel.onSelectedInputLoss = { [weak self, weak session] in
            Task { @MainActor [weak self] in
                guard let self,
                      self.inputGeneration == sessionInputGeneration,
                      self.midiSession === session
                else { return }
                await self.handleSelectedInputLoss()
            }
        }
        await sessionRecorder.configureAnalysis(
            plan: prepared.performancePlan,
            measureSpans: prepared.measureSpans,
            activeTickRange: activeRange.tickRange,
            tempoScale: configuration.tempoScale
        )
        _ = await sessionRecorder.setGuiding(true)
        guard generation == loadGeneration,
              inputGeneration == sessionInputGeneration,
              midiSession === session,
              state == .guiding
        else {
            session.shutdown()
            return
        }
        session.update(configuration: MIDIPracticeSession.Configuration(
            acceptsInput: true,
            currentStepIndex: currentStepIndex,
            expectedNotes: sessionController.expectedNotesForCurrentStep()
        ))
    }

    func replayActiveRange() async {
        guard canReplayActiveRange,
              let prepared = preparedPractice,
              let playbackService = referencePlaybackService,
              let configuration,
              let activeRange,
              let stepRange = activeRange.clampedStepRange(prepared.steps.indices),
              prepared.steps.indices.contains(stepRange.lowerBound)
        else { return }
        guard await stopTakeRecordingIfNeeded() else {
            state = .saveFailed
            errorMessage = "录制 take 尚未保存；请重试保存后再回放。"
            return
        }

        let startIndex = stepRange.lowerBound
        let startTick = prepared.steps[startIndex].tick
        let endTick = prepared.steps.indices.contains(stepRange.upperBound)
            ? prepared.steps[stepRange.upperBound].tick
            : activeRange.tickRange.upperBound

        await cancelManualReplay(restorePracticeInput: false)
        sessionController.state.manualReplayGeneration &+= 1
        let generation = sessionController.state.manualReplayGeneration
        sessionController.state.isManualReplayPlaying = true
        sessionController.state.acceptsPracticeAttempts = false
        currentStepIndex = startIndex
        midiSession?.update(configuration: MIDIPracticeSession.Configuration(
            acceptsInput: false,
            currentStepIndex: currentStepIndex,
            expectedNotes: []
        ))
        manualReplayTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var completedReplay = false
            defer {
                if self.sessionController.state.manualReplayGeneration == generation {
                    if completedReplay {
                        self.currentStepIndex = startIndex
                    }
                    self.manualReplayTask = nil
                    self.sessionController.state.isManualReplayPlaying = false
                    self.restorePracticeInputAfterManualReplay()
                }
            }

            let timeline = await AutoplayPerformanceTimeline.buildOffMain(
                plan: prepared.performancePlan,
                guideProjection: [],
                stepProjection: [],
                tempoMap: self.sessionController.state.tempoMap,
                practiceHandMode: configuration.handMode,
                activeRange: activeRange,
                transportStartTick: startTick
            )
            guard Task.isCancelled == false,
                  self.sessionController.state.manualReplayGeneration == generation
            else { return }

            do {
                try await playbackService.warmUp()
                let sequence = try await self.playbackSequenceBuilder.buildPerformanceSequence(
                    timeline: timeline,
                    tempoMap: self.sessionController.state.tempoMap,
                    startTick: startTick,
                    endTick: endTick,
                    leadInSeconds: 0.05
                )
                guard Task.isCancelled == false,
                      self.sessionController.state.manualReplayGeneration == generation
                else { return }
                await playbackService.stop(resetCommands: PerformanceTransportReducer.fullResetCommands)
                try await playbackService.load(sequence: sequence)
                try await playbackService.play(fromSeconds: 0)
                try await Task.sleep(for: .seconds(max(0, sequence.durationSeconds)))
                guard Task.isCancelled == false,
                      self.sessionController.state.manualReplayGeneration == generation
                else { return }
                await playbackService.stop(resetCommands: PerformanceTransportReducer.fullResetCommands)
                completedReplay = true
            } catch is CancellationError {
                return
            } catch {
                self.sessionController.state.recordPlaybackError(error)
                self.errorMessage = "无法回放所选练习范围。请检查所选 MIDI 输出。"
            }
        }
    }

    private func handle(_ event: MIDIPracticeSession.Event) {
        guard state == .guiding else { return }
        switch event {
        case let .inputRunning(isRunning):
            sessionController.state.isPracticeInputRunning = isRunning
        case let .inputCapabilitiesAvailable(capabilities):
            Task { [sessionRecorder] in
                await sessionRecorder.registerInputCapabilities(capabilities)
            }
        case .inputDiscontinuity:
            break
        case let .attemptEvaluated(outcome):
            sessionController.recordAttempt(outcome)
        case .advanceToNextStep:
            switch sessionController.advance() {
            case let .guiding(currentStepIndex, expectedNotes):
                midiSession?.update(configuration: MIDIPracticeSession.Configuration(
                    acceptsInput: true,
                    currentStepIndex: currentStepIndex,
                    expectedNotes: expectedNotes
                ))
            case let .completed(waitingForAssessment):
                state = .completed
                midiSession?.stop()
                if waitingForAssessment, let midiSession {
                    startPassageAnalysis(for: midiSession)
                }
            }
        }
    }

    @discardableResult
    func applyPendingRoundConfiguration() async -> Bool {
        guard let prepared = preparedPractice else { return false }
        guard await stopTakeRecordingIfNeeded() else {
            state = .saveFailed
            errorMessage = "录制 take 尚未保存；请重试后再调整练习设置。"
            return false
        }

        await stopActiveInputForRoundReconfiguration()
        let resolvedRange: PracticeActiveRange
        do {
            resolvedRange = try sessionController.applyPendingConfiguration()
        } catch {
            state = .preparationFailed
            errorMessage = "所选练习范围无效。"
            return false
        }

        guard await flushProgress() else {
            state = .saveFailed
            errorMessage = "新的练习配置暂时无法保存；请重试。"
            return false
        }

        await startGuidingInput(
            prepared: prepared,
            activeRange: resolvedRange,
            generation: loadGeneration,
            startsVisit: false
        )
        return state == .guiding
    }

    private func handleSelectedInputLoss() async {
        guard state == .guiding else { return }
        state = .inputUnavailable
        errorMessage = "所选 MIDI 输入已断开。请重新连接或重新选择设备。"
        _ = await finishCurrentPractice()
    }

    private func finishCurrentPractice() async -> Bool {
        await waitForPassageAnalysis()
        if let midiSession {
            let finished = await midiSession.finish(termination: .init(
                resetOutput: { [weak self, midiSettingsViewModel] in
                    await self?.takePlaybackViewModel.stop()
                    await self?.stopReferencePlayback()
                    midiSettingsViewModel.resetSelectedOutput()
                },
                flushProgress: { [weak self] in
                    await self?.flushProgress() ?? true
                },
                flushInputEffects: { [weak self] in
                    await self?.stopTakeRecordingIfNeeded() ?? true
                }
            ))
            guard finished else {
                state = .saveFailed
                errorMessage = pendingTake == nil
                    ? "练习进度尚未保存；请重试保存后再返回。"
                    : "录制 take 尚未保存；请重试保存后再返回。"
                return false
            }
        } else {
            guard await stopTakeRecordingIfNeeded() else {
                state = .saveFailed
                errorMessage = "录制 take 尚未保存；请重试保存后再返回。"
                return false
            }
            guard await flushProgress() else {
                state = .saveFailed
                errorMessage = "练习进度尚未保存；请重试保存后再返回。"
                return false
            }
        }
        _ = await sessionRecorder.setGuiding(false)
        let recorderStatus = await sessionRecorder.finalize()
        guard recorderStatus.permitsExit else {
            state = .saveFailed
            errorMessage = "练习记录尚未保存；请重试保存后再返回。"
            return false
        }
        return true
    }

    private func flushProgress() async -> Bool {
        guard let progress else { return true }
        do {
            try await progressRepository.upsert(progress)
            return true
        } catch {
            return false
        }
    }

    private func discardCurrentPractice() async {
        loadGeneration &+= 1
        inputGeneration &+= 1
        await cancelPassageAnalysis()
        await takePlaybackViewModel.stop()
        await takePlaybackViewModel.replaceController(nil)
        takePlaybackOutputEndpointID = nil
        await stopReferencePlayback()
        midiSession?.shutdown()
        midiSession = nil
        midiSettingsViewModel.onSelectedInputLoss = nil
        midiSettingsViewModel.resumeSelectedInputMonitoring()
        await sessionRecorder.discardPendingDelta()
        isRecordingTake = false
        recordingTakeStartedAt = nil
        pendingTake = nil
        sessionController.reset()
        loadedSongID = nil
        state = .idle
    }

    private func stopActiveInputForRoundReconfiguration() async {
        await cancelPassageAnalysis()
        inputGeneration &+= 1
        await stopReferencePlayback()
        midiSession?.shutdown()
        midiSession = nil
        midiSettingsViewModel.onSelectedInputLoss = nil
        midiSettingsViewModel.resumeSelectedInputMonitoring()
        _ = await sessionRecorder.setGuiding(false)
    }

    private func stopReferencePlayback() async {
        await cancelManualReplay(restorePracticeInput: false)
        guard let referencePlaybackService else { return }
        await referencePlaybackService.stop(
            resetCommands: PerformanceTransportReducer.fullResetCommands
        )
        self.referencePlaybackService = nil
    }

    func startTakeRecording() async {
        guard canToggleTakeRecording else { return }
        guard pendingTake == nil else {
            errorMessage = "上一段录制尚未保存；请先重试保存。"
            return
        }
        await takePlaybackViewModel.stop()
        takeRecorder.start(
            now: ProcessInfo.processInfo.systemUptime,
            metadata: RecordingTakeMetadata(
                scoreIdentity: preparedPractice?.performancePlan.sourceScoreIdentity,
                inputSources: RecordingTakeMetadata.unattributed.inputSources
            )
        )
        isRecordingTake = true
        recordingTakeStartedAt = .now
        errorMessage = nil
    }

    @discardableResult
    func stopTakeRecording() async -> Bool {
        await stopTakeRecordingIfNeeded()
    }

    func playOrPauseTake(_ take: RecordingTake) async {
        guard isRecordingTake == false else {
            errorMessage = "请先停止录制，再播放 MIDI take。"
            return
        }
        guard let outputEndpointID = midiSettingsViewModel.selectedAvailableOutputEndpointID else {
            errorMessage = "请选择可用的 MIDI 输出后再播放录制。"
            return
        }
        await cancelManualReplay(restorePracticeInput: false)
        if takePlaybackOutputEndpointID != outputEndpointID {
            await takePlaybackViewModel.replaceController(TakePlaybackController(
                playbackService: makeReferencePlaybackService(outputEndpointID)
            ))
            takePlaybackOutputEndpointID = outputEndpointID
        }
        do {
            try await takePlaybackViewModel.playOrPause(take: take)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopTakePlayback() async {
        await takePlaybackViewModel.stop()
    }

    func toggleCurrentTakePlayback() async {
        guard await matchesSelectedTakePlaybackOutput() else { return }
        do {
            try await takePlaybackViewModel.toggleCurrentPlayback()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func seekTakePlayback(to seconds: TimeInterval) async {
        guard await matchesSelectedTakePlaybackOutput() else { return }
        do {
            try await takePlaybackViewModel.seek(toSeconds: seconds)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteTake(_ take: RecordingTake) async {
        if takePlaybackViewModel.currentTakeID == take.id {
            await takePlaybackViewModel.stop()
        }
        guard takeLibraryViewModel.delete(takeID: take.id) else {
            errorMessage = takeLibraryViewModel.errorMessage
            return
        }
    }

    func renameTake(_ take: RecordingTake, to proposedName: String) {
        let name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.isEmpty == false else {
            errorMessage = "录制名称不能为空。"
            return
        }
        guard takeLibraryViewModel.rename(takeID: take.id, to: name) else {
            errorMessage = takeLibraryViewModel.errorMessage
            return
        }
    }

    func clearAllTakes() async {
        await takePlaybackViewModel.stop()
        guard takeLibraryViewModel.clearAll() else {
            errorMessage = takeLibraryViewModel.errorMessage
            return
        }
    }

    func makeMIDIExport(for take: RecordingTake) -> RecordingMIDIExport? {
        do {
            return try takeLibraryViewModel.makeMIDIExport(for: take)
        } catch {
            errorMessage = "无法导出该录制：\(error.localizedDescription)"
            return nil
        }
    }

    func dismissError() {
        errorMessage = nil
        takeLibraryViewModel.dismissError()
    }

    private func recordTakeObservation(_ observation: PerformanceObservation) {
        guard isRecordingTake else { return }
        takeRecorder.record(observation)
    }

    private func matchesSelectedTakePlaybackOutput() async -> Bool {
        guard let outputEndpointID = midiSettingsViewModel.selectedAvailableOutputEndpointID else {
            errorMessage = "请选择可用的 MIDI 输出后再播放录制。"
            return false
        }
        guard takePlaybackOutputEndpointID == outputEndpointID else {
            await takePlaybackViewModel.replaceController(nil)
            takePlaybackOutputEndpointID = nil
            errorMessage = "MIDI 输出已改变；请重新播放录制。"
            return false
        }
        return true
    }

    private func stopTakeRecordingIfNeeded() async -> Bool {
        if isRecordingTake {
            isRecordingTake = false
            recordingTakeStartedAt = nil
            let take = takeRecorder.stop(now: ProcessInfo.processInfo.systemUptime)
            pendingTake = take.events.isEmpty ? nil : take
        }
        guard let pendingTake else { return true }
        guard takeLibraryViewModel.addTake(pendingTake) else {
            errorMessage = takeLibraryViewModel.errorMessage
            return false
        }
        self.pendingTake = nil
        return true
    }

    private func cancelManualReplay(restorePracticeInput: Bool) async {
        let wasReplaying = sessionController.state.isManualReplayPlaying
        sessionController.state.manualReplayGeneration &+= 1
        let task = manualReplayTask
        manualReplayTask = nil
        task?.cancel()
        await task?.value
        sessionController.state.isManualReplayPlaying = false
        if wasReplaying, let referencePlaybackService {
            await referencePlaybackService.stop(
                resetCommands: PerformanceTransportReducer.fullResetCommands
            )
        }
        if restorePracticeInput {
            restorePracticeInputAfterManualReplay()
        }
    }

    private func restorePracticeInputAfterManualReplay() {
        sessionController.state.acceptsPracticeAttempts = true
        guard state == .guiding else { return }
        midiSession?.update(configuration: MIDIPracticeSession.Configuration(
            acceptsInput: true,
            currentStepIndex: currentStepIndex,
            expectedNotes: sessionController.expectedNotesForCurrentStep()
        ))
    }

    @discardableResult
    func applyCurrentCoachingAction() async -> Bool {
        guard let decision = currentCoachingDecision,
              sessionController.stageCurrentCoachingRound()
        else { return false }

        guard await applyPendingRoundConfiguration() else { return false }
        await sessionController.acceptCoachingDecision(decision)
        if decision.action.referenceUse == .manualReplay {
            await replayActiveRange()
        }
        return true
    }

    func skipCurrentCoachingAction() async {
        await sessionController.skipCurrentCoachingDecision()
    }

    private func startPassageAnalysis(for midiSession: MIDIPracticeSession) {
        passageAnalysisGeneration &+= 1
        let generation = passageAnalysisGeneration
        let sessionGeneration = loadGeneration
        passageAnalysisTask?.cancel()
        passageAnalysisTask = Task { @MainActor [weak self, weak midiSession] in
            guard let self, let midiSession else { return }
            await midiSession.waitForPendingObservationRecording()
            guard Task.isCancelled == false,
                  self.passageAnalysisGeneration == generation,
                  self.loadGeneration == sessionGeneration,
                  self.midiSession === midiSession,
                  self.state == .completed
            else { return }

            _ = await self.sessionRecorder.setGuiding(false)
            let snapshot = await self.sessionRecorder.analysisSnapshot()
            guard Task.isCancelled == false,
                  self.passageAnalysisGeneration == generation,
                  self.loadGeneration == sessionGeneration,
                  self.midiSession === midiSession,
                  self.state == .completed
            else { return }

            self.retireCompletedInput(midiSession)
            let advance = await self.sessionController.completePassageAnalysis(
                assessment: snapshot.assessment,
                analyzerRoundGeneration: snapshot.roundGeneration
            )
            guard Task.isCancelled == false,
                  self.passageAnalysisGeneration == generation,
                  self.loadGeneration == sessionGeneration
            else { return }
            guard await self.flushProgress() else {
                self.state = .saveFailed
                self.errorMessage = "本轮评估结果暂时无法保存；请重试。"
                return
            }

            switch advance {
            case let .guiding(currentStepIndex, _):
                guard let prepared = self.preparedPractice,
                      let activeRange = self.activeRange
                else { return }
                self.currentStepIndex = currentStepIndex
                await self.startGuidingInput(
                    prepared: prepared,
                    activeRange: activeRange,
                    generation: sessionGeneration,
                    startsVisit: false
                )
            case .completed:
                self.state = .completed
            }

            if self.passageAnalysisGeneration == generation {
                self.passageAnalysisTask = nil
            }
        }
    }

    private func retireCompletedInput(_ midiSession: MIDIPracticeSession) {
        guard self.midiSession === midiSession else { return }
        inputGeneration &+= 1
        midiSession.shutdown()
        self.midiSession = nil
        midiSettingsViewModel.onSelectedInputLoss = nil
        midiSettingsViewModel.resumeSelectedInputMonitoring()
        sessionController.state.isPracticeInputRunning = false
    }

    private func waitForPassageAnalysis() async {
        await passageAnalysisTask?.value
    }

    private func cancelPassageAnalysis() async {
        passageAnalysisGeneration &+= 1
        let task = passageAnalysisTask
        passageAnalysisTask = nil
        task?.cancel()
        await task?.value
    }
}
