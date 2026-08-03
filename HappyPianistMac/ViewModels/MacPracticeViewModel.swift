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
    private let roundState: MacPracticeRoundStateStore

    let roundConfigurationController: PracticeRoundConfigurationController

    private let stepNavigator = PracticeStepNavigator()
    private let attemptReducer = PracticeAttemptReducer()
    private var attemptReductionState = PracticeAttemptReductionState()
    private var measureIndex: PracticeMeasureIndex?
    private var activeRange: PracticeActiveRange?
    private var progress: SongPracticeProgress?
    private var midiSession: MIDIPracticeSession?
    private var referencePlaybackService: (any PracticeSequencerPlaybackServiceProtocol)?
    @ObservationIgnored private var midiEventTask: Task<Void, Never>?
    private var loadedSongID: UUID?
    private var loadGeneration = 0
    private var inputGeneration = 0

    private(set) var state: MacPracticeState = .idle
    private(set) var preparedPractice: PreparedPractice?
    private(set) var currentStepIndex = 0
    private(set) var lastAttempt: StepAttemptMatchResult?
    private(set) var errorMessage: String?

    var canPlayCurrentStepReference: Bool {
        state == .guiding &&
            referencePlaybackService != nil &&
            midiSettingsViewModel.selectedAvailableOutputEndpointID != nil &&
            preparedPractice?.steps.indices.contains(currentStepIndex) == true &&
            activeRange?.contains(stepIndex: currentStepIndex) == true
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
        let roundState = MacPracticeRoundStateStore()
        self.roundState = roundState
        roundConfigurationController = PracticeRoundConfigurationController(
            stateStore: roundState,
            settingsProvider: settingsProvider,
            defaultsStore: roundDefaultsStore
        )
    }

    private var configuration: PracticeRoundConfiguration? {
        roundState.activeRoundConfiguration
    }

    func load(songID: UUID) async {
        guard loadedSongID != songID || preparedPractice == nil else { return }
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

    func retrySavingAndReturn() async -> Bool {
        guard state == .saveFailed else { return false }
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
        let measureIndex = PracticeMeasureIndex(steps: prepared.steps, measureSpans: prepared.measureSpans)
        guard let first = measureIndex.measureSpans.first?.occurrenceID,
              let last = measureIndex.measureSpans.last?.occurrenceID,
              let passage = PracticePassage(start: first, end: last)
        else {
            state = .preparationFailed
            errorMessage = "曲谱缺少可练习的小节结构。"
            return
        }
        self.measureIndex = measureIndex
        roundConfigurationController.installFreshFullScoreConfiguration(passage: passage)
        guard let freshConfiguration = configuration else {
            state = .preparationFailed
            errorMessage = "无法创建练习配置。"
            return
        }

        var resolvedRange = try measureIndex.resolve(freshConfiguration.passage)
        var effectiveProgress = restoredProgress
        if let restoredProgress {
            let restoration = PracticeExactProgressRestorer.restore(
                restoredProgress,
                freshConfiguration: freshConfiguration,
                measureIndex: measureIndex
            )
            effectiveProgress = restoration.progress
            if let restoredConfiguration = restoration.progress.activeConfiguration {
                roundConfigurationController.restoreActiveConfiguration(restoredConfiguration)
                if let restoredRange = restoration.activeRange {
                    resolvedRange = restoredRange
                }
            }
            if restoration.didRepairSavedState {
                do {
                    try await progressRepository.upsert(restoration.progress)
                } catch {
                    guard generation == loadGeneration else { return }
                    state = .saveFailed
                    errorMessage = "已修复的练习状态暂时无法保存；请恢复后重试。"
                    return
                }
            }
        }

        guard generation == loadGeneration else { return }
        activeRange = resolvedRange
        progress = effectiveProgress
        attemptReductionState = PracticeAttemptReductionState()
        preparedPractice = prepared
        currentStepIndex = effectiveProgress?.resumePoint?.stepIndex ?? resolvedRange.firstStepIndex
        lastAttempt = nil
        await start(prepared: prepared, activeRange: resolvedRange, generation: generation)
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
        let session = MIDIPracticeSession(
            inputEventSource: input,
            diagnosticsReporter: diagnosticsReporter,
            observationRecorder: sessionRecorder
        )
        midiSession = session
        let sessionInputGeneration = bind(session: session)
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
            expectedNotes: expectedNotesForCurrentStep(in: prepared, configuration: configuration)
        ))
    }

    func playCurrentStepReference() async {
        guard canPlayCurrentStepReference,
              let prepared = preparedPractice,
              let playbackService = referencePlaybackService,
              let configuration
        else { return }

        let commands = expectedNotesForCurrentStep(in: prepared, configuration: configuration).compactMap { note -> PracticePlaybackCommand? in
            guard UInt8(exactly: note.midiNote) != nil else { return nil }
            return PracticePlaybackCommand(
                sourceEventID: "mac-reference-\(currentStepIndex)-\(note.id)",
                kind: .noteOn(midi: note.midiNote, velocity: note.velocity)
            )
        }
        guard commands.isEmpty == false else { return }

        do {
            try await playbackService.playOneShot(
                commands: commands,
                durationSeconds: 0.5 / configuration.tempoScale
            )
        } catch {
            errorMessage = "无法播放当前步骤参考音。请检查所选 MIDI 输出。"
        }
    }

    @discardableResult
    private func bind(session: MIDIPracticeSession) -> Int {
        midiEventTask?.cancel()
        inputGeneration &+= 1
        let generation = inputGeneration
        midiEventTask = Task { [weak self, weak session] in
            guard let session else { return }
            for await event in session.events() {
                guard let self,
                      self.inputGeneration == generation,
                      self.midiSession === session
                else { return }
                self.handle(event)
            }
        }
        return generation
    }

    private func handle(_ event: MIDIPracticeSession.Event) {
        guard state == .guiding,
              let prepared = preparedPractice,
              let configuration,
              let measureIndex,
              let activeRange
        else { return }
        switch event {
        case .inputRunning, .inputCapabilitiesAvailable, .inputDiscontinuity:
            break
        case let .attemptEvaluated(outcome):
            lastAttempt = outcome
            let result = attemptReducer.reduceAttempt(
                progress: progress,
                reductionState: attemptReductionState,
                outcome: outcome,
                stepIndex: currentStepIndex,
                identity: prepared.identity,
                configuration: configuration,
                measureIndex: measureIndex,
                timestamp: .now
            )
            progress = result.progress
            attemptReductionState = result.reductionState
        case .advanceToNextStep:
            let navigation = stepNavigator.advance(
                steps: prepared.steps,
                currentStepIndex: currentStepIndex,
                activeRange: activeRange
            )
            currentStepIndex = navigation.currentStepIndex
            switch navigation.state {
            case .guiding:
                updateResumePoint()
                midiSession?.update(configuration: MIDIPracticeSession.Configuration(
                    acceptsInput: true,
                    currentStepIndex: currentStepIndex,
                    expectedNotes: expectedNotesForCurrentStep(in: prepared, configuration: configuration)
                ))
            case .completed:
                recordPassageCompletion(configuration: configuration, identity: prepared.identity)
                if configuration.loopEnabled {
                    beginNextLoopRound(
                        prepared: prepared,
                        configuration: configuration,
                        activeRange: activeRange
                    )
                } else {
                    state = .completed
                    midiSession?.stop()
                }
            default:
                break
            }
        }
    }

    @discardableResult
    func applyPendingRoundConfiguration() async -> Bool {
        guard let prepared = preparedPractice,
              let measureIndex
        else { return false }

        await stopActiveInputForRoundReconfiguration()
        _ = roundConfigurationController.applyPending()
        guard let configuration else {
            state = .preparationFailed
            errorMessage = "练习配置无效。"
            return false
        }

        let resolvedRange: PracticeActiveRange
        do {
            resolvedRange = try measureIndex.resolve(configuration.passage)
        } catch {
            state = .preparationFailed
            errorMessage = "所选练习范围无效。"
            return false
        }

        activeRange = resolvedRange
        currentStepIndex = resolvedRange.firstStepIndex
        attemptReductionState = PracticeAttemptReductionState()
        lastAttempt = nil
        let restart = attemptReducer.reducePassageRestart(
            progress: progress,
            identity: prepared.identity,
            configuration: configuration,
            timestamp: .now
        )
        var restartedProgress = restart.progress
        restartedProgress.resumePoint = nil
        progress = restartedProgress
        attemptReductionState = restart.reductionState
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
        if let midiSession {
            let finished = await midiSession.finish(termination: .init(
                resetOutput: { [weak self, midiSettingsViewModel] in
                    await self?.stopReferencePlayback()
                    midiSettingsViewModel.resetSelectedOutput()
                },
                flushProgress: { [weak self] in
                    await self?.flushProgress() ?? true
                }
            ))
            guard finished else {
                state = .saveFailed
                errorMessage = "练习进度尚未保存；请重试保存后再返回。"
                return false
            }
        } else if await flushProgress() == false {
            state = .saveFailed
            errorMessage = "练习进度尚未保存；请重试保存后再返回。"
            return false
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
        midiEventTask?.cancel()
        midiEventTask = nil
        await stopReferencePlayback()
        midiSession?.shutdown()
        midiSession = nil
        midiSettingsViewModel.onSelectedInputLoss = nil
        midiSettingsViewModel.resumeSelectedInputMonitoring()
        await sessionRecorder.discardPendingDelta()
        measureIndex = nil
        activeRange = nil
        roundConfigurationController.resetSong()
        progress = nil
        preparedPractice = nil
        loadedSongID = nil
        attemptReductionState = PracticeAttemptReductionState()
        currentStepIndex = 0
        lastAttempt = nil
        state = .idle
    }

    private func stopActiveInputForRoundReconfiguration() async {
        inputGeneration &+= 1
        midiEventTask?.cancel()
        midiEventTask = nil
        await stopReferencePlayback()
        midiSession?.shutdown()
        midiSession = nil
        midiSettingsViewModel.onSelectedInputLoss = nil
        midiSettingsViewModel.resumeSelectedInputMonitoring()
        _ = await sessionRecorder.setGuiding(false)
    }

    private func expectedNotesForCurrentStep(
        in prepared: PreparedPractice,
        configuration: PracticeRoundConfiguration
    ) -> [PracticeStepNote] {
        guard prepared.steps.indices.contains(currentStepIndex) else { return [] }
        let notes = prepared.steps[currentStepIndex].notes
        guard configuration.handMode != .both else { return notes }
        return notes.filter { configuration.handMode.allows(hand: $0.hand) }
    }

    private func updateResumePoint() {
        guard let measureIndex,
              let occurrenceID = measureIndex.occurrenceID(forStepIndex: currentStepIndex),
              var progress
        else { return }
        progress.resumePoint = PracticeResumePoint(
            occurrenceID: occurrenceID,
            stepIndex: currentStepIndex,
            updatedAt: .now
        )
        progress.updatedAt = .now
        self.progress = progress
    }

    private func recordPassageCompletion(
        configuration: PracticeRoundConfiguration,
        identity: PracticeSongIdentity
    ) {
        let result = attemptReducer.reducePassageCompletion(
            progress: progress,
            reductionState: attemptReductionState,
            identity: identity,
            configuration: configuration,
            timestamp: .now
        )
        progress = result.progress
        attemptReductionState = result.reductionState
    }

    private func beginNextLoopRound(
        prepared: PreparedPractice,
        configuration: PracticeRoundConfiguration,
        activeRange: PracticeActiveRange
    ) {
        roundConfigurationController.beginNextRound()
        let restart = attemptReducer.reducePassageRestart(
            progress: progress,
            identity: prepared.identity,
            configuration: configuration,
            timestamp: .now
        )
        progress = restart.progress
        attemptReductionState = restart.reductionState
        currentStepIndex = activeRange.firstStepIndex
        updateResumePoint()
        lastAttempt = nil
        midiSession?.update(configuration: MIDIPracticeSession.Configuration(
            acceptsInput: true,
            currentStepIndex: currentStepIndex,
            expectedNotes: expectedNotesForCurrentStep(in: prepared, configuration: configuration)
        ))
    }

    private func stopReferencePlayback() async {
        guard let referencePlaybackService else { return }
        await referencePlaybackService.stop(
            resetCommands: PerformanceTransportReducer.fullResetCommands
        )
        self.referencePlaybackService = nil
    }
}

@MainActor
@Observable
private final class MacPracticeRoundStateStore: PracticeRoundConfigurationStateStoring {
    var activeRoundConfiguration: PracticeRoundConfiguration?
    var activeManualAdvanceMode: ManualAdvanceMode = .step
    var activeSoundRoutingSettings = PracticeSoundRoutingSettings(
        outputRoute: .localSampler,
        midiDestinationUniqueID: nil,
        sendLocalControlOff: false
    )
    var roundGeneration = 0
}
