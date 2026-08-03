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
    private let diagnosticsReporter: (any DiagnosticsReporting)?

    private let stepNavigator = PracticeStepNavigator()
    private let attemptReducer = PracticeAttemptReducer()
    private var attemptReductionState = PracticeAttemptReductionState()
    private var measureIndex: PracticeMeasureIndex?
    private var configuration: PracticeRoundConfiguration?
    private var progress: SongPracticeProgress?
    private var midiSession: MIDIPracticeSession?
    @ObservationIgnored private var midiEventTask: Task<Void, Never>?
    private var loadedSongID: UUID?
    private var loadGeneration = 0

    private(set) var state: MacPracticeState = .idle
    private(set) var preparedPractice: PreparedPractice?
    private(set) var currentStepIndex = 0
    private(set) var lastAttempt: StepAttemptMatchResult?
    private(set) var errorMessage: String?

    init(
        resolveEntry: @escaping @Sendable (UUID) async -> Result<ResolvedSongLibraryEntry, SongLibraryEntryResolutionError>,
        preparationService: any PracticePreparationServiceProtocol,
        progressRepository: any PracticeProgressRepositoryProtocol,
        progressRecovery: (any PracticeProgressRecoveryProtocol)? = nil,
        sessionRecorder: PracticeSessionRecorder,
        midiSettingsViewModel: MIDISettingsViewModel,
        diagnosticsReporter: (any DiagnosticsReporting)? = nil
    ) {
        self.resolveEntry = resolveEntry
        self.preparationService = preparationService
        self.progressRepository = progressRepository
        self.progressRecovery = progressRecovery
        self.sessionRecorder = sessionRecorder
        self.midiSettingsViewModel = midiSettingsViewModel
        self.diagnosticsReporter = diagnosticsReporter
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
        let activeRange = try measureIndex.resolve(passage)
        let configuration = PracticeRoundConfiguration(
            passage: passage,
            handMode: .both,
            tempoScale: 1,
            loopEnabled: false,
            requiredSuccesses: 1
        )
        self.measureIndex = measureIndex
        self.configuration = configuration
        progress = restoredProgress
        attemptReductionState = PracticeAttemptReductionState()
        preparedPractice = prepared
        currentStepIndex = activeRange.firstStepIndex
        lastAttempt = nil
        await start(prepared: prepared, activeRange: activeRange, generation: generation)
    }

    private func start(
        prepared: PreparedPractice,
        activeRange: PracticeActiveRange,
        generation: Int
    ) async {
        midiSettingsViewModel.load()
        guard let input = midiSettingsViewModel.selectedInputForPractice() else {
            state = .inputUnavailable
            errorMessage = "请选择可用的 MIDI 输入后再开始练习。"
            return
        }
        state = .guiding
        errorMessage = nil
        let session = MIDIPracticeSession(
            inputEventSource: input,
            diagnosticsReporter: diagnosticsReporter,
            observationRecorder: sessionRecorder
        )
        midiSession = session
        bind(session: session)
        midiSettingsViewModel.onSelectedInputLoss = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.handleSelectedInputLoss()
            }
        }
        _ = await sessionRecorder.beginVisit(
            id: UUID(),
            songID: prepared.identity.songID,
            sceneIsActive: true
        )
        _ = await sessionRecorder.bindIdentity(prepared.identity)
        await sessionRecorder.configureAnalysis(
            plan: prepared.performancePlan,
            measureSpans: prepared.measureSpans,
            activeTickRange: activeRange.tickRange
        )
        _ = await sessionRecorder.setGuiding(true)
        guard generation == loadGeneration,
              midiSession === session,
              state == .guiding
        else {
            return
        }
        session.update(configuration: MIDIPracticeSession.Configuration(
            acceptsInput: true,
            currentStepIndex: currentStepIndex,
            expectedNotes: prepared.steps[currentStepIndex].notes
        ))
    }

    private func bind(session: MIDIPracticeSession) {
        midiEventTask?.cancel()
        midiEventTask = Task { [weak self] in
            for await event in session.events() {
                self?.handle(event)
            }
        }
    }

    private func handle(_ event: MIDIPracticeSession.Event) {
        guard state == .guiding,
              let prepared = preparedPractice,
              let configuration,
              let measureIndex
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
                currentStepIndex: currentStepIndex
            )
            currentStepIndex = navigation.currentStepIndex
            switch navigation.state {
            case .guiding:
                midiSession?.update(configuration: MIDIPracticeSession.Configuration(
                    acceptsInput: true,
                    currentStepIndex: currentStepIndex,
                    expectedNotes: prepared.steps[currentStepIndex].notes
                ))
            case .completed:
                state = .completed
                midiSession?.stop()
            default:
                break
            }
        }
    }

    private func handleSelectedInputLoss() async {
        guard state == .guiding else { return }
        state = .inputUnavailable
        errorMessage = "所选 MIDI 输入已断开。请重新连接或重新选择设备。"
        _ = await finishCurrentPractice()
    }

    private func finishCurrentPractice() async -> Bool {
        guard let midiSession else { return true }
        let finished = await midiSession.finish(termination: .init(
            resetOutput: { [midiSettingsViewModel] in
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
        midiEventTask?.cancel()
        midiEventTask = nil
        midiSession?.shutdown()
        midiSession = nil
        midiSettingsViewModel.onSelectedInputLoss = nil
        midiSettingsViewModel.resumeSelectedInputMonitoring()
        await sessionRecorder.discardPendingDelta()
        measureIndex = nil
        configuration = nil
        progress = nil
        preparedPractice = nil
        loadedSongID = nil
        attemptReductionState = PracticeAttemptReductionState()
        currentStepIndex = 0
        lastAttempt = nil
        state = .idle
    }
}
