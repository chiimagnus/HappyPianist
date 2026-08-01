import Foundation
import Observation

@MainActor
protocol PracticeLaunchApplying: AnyObject, Sendable {
    func applyPreparedPracticeForLaunch(
        _ prepared: PreparedPractice,
        restorePolicy: PracticeLaunchRestorePolicy,
        isCurrent: @escaping @MainActor () -> Bool
    ) async -> PracticeLaunchApplyOutcome?
    func setPracticeGuidingStartBlocked(_ isBlocked: Bool)
    func clearPreparedPracticeForLaunch() async -> PracticeProgressSaveStatus
    func commitPreparedPracticeReturn()
    func suspendPracticeAndFlushProgress() async
}

private struct PracticeLaunchReturnContext {
    let operationID: UUID
    let requestedSongID: UUID?
    let state: PracticeLaunchState?
}

@MainActor
@Observable
final class PracticeLaunchViewModel {
    private let resolver: any SongLibraryEntryResolving
    private let preparationService: any PracticePreparationServiceProtocol
    private let applicator: any PracticeLaunchApplying
    private let diagnosticsReporter: any DiagnosticsReporting
    private let progressRepository: any PracticeProgressRepositoryProtocol
    private let progressRecovery: (any PracticeProgressRecoveryProtocol)?
    private let sessionRecorder: PracticeSessionRecorder?
    private let historicalPreferencesResolver: PracticeHistoricalPreferencesResolver
    private let now: @Sendable () -> Date
    private let makeVisitID: @Sendable () -> UUID

    @ObservationIgnored private var activationTask: Task<Void, Never>?
    @ObservationIgnored private var retiredActivationTasks: [Task<Void, Never>] = []
    @ObservationIgnored private var metadataWriteTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var returnContext: PracticeLaunchReturnContext?
    @ObservationIgnored private(set) var currentVisitID: UUID?
    @ObservationIgnored private var reportedRecoveredSessionIDs: Set<UUID> = []

    private(set) var state: PracticeLaunchState?
    private(set) var requestedSongID: UUID?
    private(set) var activationIdentity: PracticeLaunchActivationIdentity?
    private(set) var progressAccessFailure: PracticeLaunchFailure?

    init(
        resolver: any SongLibraryEntryResolving,
        preparationService: any PracticePreparationServiceProtocol,
        applicator: any PracticeLaunchApplying,
        diagnosticsReporter: any DiagnosticsReporting,
        progressRepository: any PracticeProgressRepositoryProtocol,
        progressRecovery: (any PracticeProgressRecoveryProtocol)? = nil,
        sessionRecorder: PracticeSessionRecorder? = nil,
        historicalPreferencesResolver: PracticeHistoricalPreferencesResolver = PracticeHistoricalPreferencesResolver(),
        now: @escaping @Sendable () -> Date = { .now },
        makeVisitID: @escaping @Sendable () -> UUID = { UUID() }
    ) {
        self.resolver = resolver
        self.preparationService = preparationService
        self.applicator = applicator
        self.diagnosticsReporter = diagnosticsReporter
        self.progressRepository = progressRepository
        self.progressRecovery = progressRecovery
        self.sessionRecorder = sessionRecorder
        self.historicalPreferencesResolver = historicalPreferencesResolver
        self.now = now
        self.makeVisitID = makeVisitID
    }

    func request(songID: UUID) {
        if requestedSongID == songID, let state {
            switch state {
            case .requested, .loading, .ready:
                return
            case .failure:
                break
            }
        }
        registerRequest(
            songID: songID,
            startsNewVisit: requestedSongID != songID || currentVisitID == nil
        )
    }

    func activateCurrentRequest() async {
        await sessionRecorder?.setSceneActive(true)
        guard activationTask == nil,
              let songID = requestedSongID,
              case .requested(songID) = state
        else { return }
        let currentGeneration = generation
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performActivation(songID: songID, generation: currentGeneration)
        }
        activationTask = task
        await task.value
        if generation == currentGeneration {
            activationTask = nil
        }
    }

    func retry() async {
        guard let songID = requestedSongID else { return }
        registerRequest(songID: songID, startsNewVisit: false)
        await activateCurrentRequest()
    }

    func recoverCorruptedProgress() async {
        guard let songID = requestedSongID,
              case let .ready(identity) = state,
              let failure = progressAccessFailure,
              failure.recoveryAction == .backupAndResetCorruptedProgress,
              let progressRecovery
        else { return }

        let recoveryGeneration = generation
        state = .loading(songID: songID)
        do {
            let result = try await progressRecovery.recoverFromCorruption()
            guard isCurrentRecovery(songID: songID, generation: recoveryGeneration) else { return }
            if case .recovered = result {
                _ = await diagnosticsReporter.record(
                    DiagnosticEvent(
                        severity: .warning,
                        code: .practiceProgressStoreReset,
                        category: .persistence,
                        stage: "practiceProgressRecovery",
                        summary: "已备份并重置损坏的练习记录",
                        reason: "The user confirmed recovery and the repository replaced the corrupted store.",
                        songID: songID,
                        persistence: .exportable
                    )
                )
            }
            guard isCurrentRecovery(songID: songID, generation: recoveryGeneration) else { return }
            registerRequest(songID: songID, startsNewVisit: false)
            await activateCurrentRequest()
        } catch {
            guard isCurrentRecovery(songID: songID, generation: recoveryGeneration) else { return }
            let recoveryFailure = PracticeLaunchFailure.progressStoreUnavailable(
                entryID: songID,
                reason: PracticePreparationErrorDetails.safeErrorSummary(error)
            )
            progressAccessFailure = recoveryFailure
            state = .ready(identity)
            _ = await diagnosticsReporter.record(recoveryFailure.diagnosticEvent)
        }
    }

    func suspendForInactiveScene() async {
        await sessionRecorder?.setSceneActive(false)
        retireCurrentActivationTask()
        generation += 1
        if let songID = requestedSongID {
            state = .requested(songID: songID)
            activationIdentity = PracticeLaunchActivationIdentity(
                songID: songID,
                revision: generation
            )
        }
        await settleRetiredActivationTasks()
        await applicator.suspendPracticeAndFlushProgress()
    }

    func beginReturn() -> UUID {
        if let returnContext { return returnContext.operationID }
        retireCurrentActivationTask()
        generation += 1
        let operationID = UUID()
        returnContext = PracticeLaunchReturnContext(
            operationID: operationID,
            requestedSongID: requestedSongID,
            state: state
        )
        requestedSongID = nil
        activationIdentity = nil
        return operationID
    }

    func abortReturn(operationID: UUID) {
        guard let context = returnContext, context.operationID == operationID else { return }
        returnContext = nil
        generation += 1
        requestedSongID = context.requestedSongID
        guard let songID = context.requestedSongID else {
            state = nil
            activationIdentity = nil
            return
        }
        switch context.state {
        case .requested, .loading, nil:
            state = .requested(songID: songID)
        case .failure, .ready:
            state = context.state
        }
        activationIdentity = PracticeLaunchActivationIdentity(
            songID: songID,
            revision: generation
        )
    }

    @discardableResult
    func finishReturn(operationID: UUID) async -> PracticeProgressSaveStatus {
        guard returnContext?.operationID == operationID else { return .idle }
        await settleRetiredActivationTasks()
        await waitForMetadataWrites()
        if let sessionRecorder {
            let recorderStatus = await sessionRecorder.finalize()
            guard recorderStatus.permitsExit else {
                abortReturn(operationID: operationID)
                return .failed(message: "Practice session facts could not be saved.")
            }
        }
        guard returnContext?.operationID == operationID else {
            return .failed(message: "Return operation was superseded.")
        }
        applicator.commitPreparedPracticeReturn()
        returnContext = nil
        currentVisitID = nil
        progressAccessFailure = nil
        return .saved
    }

    @discardableResult
    func discardUnsavedChangesAndFinishReturn(
        operationID: UUID
    ) async -> PracticeProgressSaveStatus {
        guard returnContext?.operationID == operationID else { return .idle }
        await settleRetiredActivationTasks()
        await cancelAndWaitForMetadataWrites()
        await sessionRecorder?.discardPendingDelta()
        guard returnContext?.operationID == operationID else {
            return .failed(message: "Return operation was superseded.")
        }
        applicator.commitPreparedPracticeReturn()
        returnContext = nil
        currentVisitID = nil
        progressAccessFailure = nil
        return .saved
    }

    func closeForSystemDisappear() async {
        retireCurrentActivationTask()
        generation += 1
        await settleRetiredActivationTasks()
        await cancelAndWaitForMetadataWrites()
        _ = await sessionRecorder?.finalize()
        returnContext = nil
        requestedSongID = nil
        activationIdentity = nil
        currentVisitID = nil
        progressAccessFailure = nil
    }

    private func registerRequest(songID: UUID, startsNewVisit: Bool) {
        retireCurrentActivationTask()
        generation += 1
        returnContext = nil
        progressAccessFailure = nil
        if startsNewVisit || currentVisitID == nil {
            currentVisitID = makeVisitID()
        }
        requestedSongID = songID
        state = .requested(songID: songID)
        activationIdentity = PracticeLaunchActivationIdentity(
            songID: songID,
            revision: generation
        )
    }

    private func performActivation(songID: UUID, generation: Int) async {
        guard isCurrent(songID: songID, generation: generation) else { return }
        state = .loading(songID: songID)
        if let sessionRecorder, let currentVisitID {
            let recorderStatus = await sessionRecorder.beginVisit(
                id: currentVisitID,
                songID: songID,
                sceneIsActive: true
            )
            guard isCurrent(songID: songID, generation: generation) else { return }
            guard recorderStatus.permitsExit else {
                await publishRecorderFailure(songID: songID, status: recorderStatus)
                return
            }
        }
        let clearStatus = await applicator.clearPreparedPracticeForLaunch()
        guard isCurrent(songID: songID, generation: generation) else { return }
        if case .failed = clearStatus {
            let failure = PracticeLaunchFailure.progressSaveFailed(entryID: songID)
            state = .failure(failure)
            _ = await diagnosticsReporter.record(failure.diagnosticEvent)
            return
        }

        var fileReference: DiagnosticFileReference?
        do {
            let resolved = try await resolver.resolve(songID: songID)
            fileReference = resolved.diagnosticFileReference
            let history = await progressRepository.history(for: songID)
            guard isCurrent(songID: songID, generation: generation) else { return }
            let loadedHistory: PracticeSongHistory
            let accessFailure: PracticeLaunchFailure?
            switch history {
            case let .loaded(history):
                loadedHistory = history
                accessFailure = nil
                await reportRecoveredSessions(in: history)
            case let .unavailable(description):
                let failure = PracticeLaunchFailure.progressStoreUnavailable(
                    entryID: songID,
                    reason: description
                )
                loadedHistory = PracticeSongHistory(
                    songID: songID,
                    progresses: [],
                    scoreMetadata: [],
                    sessions: []
                )
                accessFailure = failure
                _ = await diagnosticsReporter.record(failure.diagnosticEvent)
            case let .corrupted(description):
                let failure = PracticeLaunchFailure.progressStoreCorrupted(
                    entryID: songID,
                    reason: description,
                    canReset: progressRecovery != nil
                )
                loadedHistory = PracticeSongHistory(
                    songID: songID,
                    progresses: [],
                    scoreMetadata: [],
                    sessions: []
                )
                accessFailure = failure
                _ = await diagnosticsReporter.record(failure.diagnosticEvent)
            }
            guard isCurrent(songID: songID, generation: generation) else { return }
            _ = await diagnosticsReporter.record(
                DiagnosticEvent(
                    severity: .info,
                    code: .practicePreparationStarted,
                    category: .practicePreparation,
                    stage: "practiceLaunchActivation",
                    summary: "开始准备曲谱练习数据",
                    reason: "A registered practice request became active.",
                    songID: songID,
                    file: fileReference,
                    persistence: .exportable
                )
            )
            _ = await diagnosticsReporter.record(
                PianoPerformanceDiagnosticSample(
                    stage: .preparation,
                    outcome: .started,
                    capability: .scoreParsing
                ).diagnosticEvent
            )
            guard isCurrent(songID: songID, generation: generation) else { return }
            let prepared = try await preparationService.prepare(
                songID: songID,
                from: resolved.scoreURL,
                file: ImportedMusicXMLFile(
                    fileName: resolved.entry.displayName,
                    storedURL: resolved.scoreURL,
                    importedAt: resolved.entry.importedAt
                )
            )
            try Task.checkCancellation()
            guard prepared.steps.isEmpty == false else {
                throw PracticePreparationError.noPlayableNotes
            }
            guard prepared.measureSpans.isEmpty == false else {
                throw PracticePreparationError.missingMeasureStructure
            }
            _ = await diagnosticsReporter.record(
                PianoPerformanceDiagnosticSample(
                    stage: .preparation,
                    outcome: .succeeded,
                    capability: .scoreParsing,
                    itemCount: prepared.steps.count
                ).diagnosticEvent
            )
            let restorePolicy = historicalPreferencesResolver.resolve(
                identity: prepared.identity,
                history: loadedHistory
            )
            let historyResolutionReason = switch restorePolicy {
            case .exactAvailable:
                "exactAvailable"
            case .historicalPreferences:
                "exactMissing:historicalCandidate"
            case .freshDefaults:
                "exactMissing:noValidCandidate"
            }
            _ = await diagnosticsReporter.record(
                DiagnosticEvent(
                    severity: .info,
                    code: .practiceHistoryResolution,
                    category: .persistence,
                    stage: "practiceHistoryResolution",
                    summary: "练习历史恢复策略已确定",
                    reason: historyResolutionReason,
                    songID: songID,
                    scoreRevision: prepared.identity.scoreRevision,
                    persistence: .systemOnly
                )
            )
            guard isCurrent(songID: songID, generation: generation) else { return }
            applicator.setPracticeGuidingStartBlocked(accessFailure != nil)
            let applyOutcome = await applicator.applyPreparedPracticeForLaunch(
                prepared,
                restorePolicy: restorePolicy,
                isCurrent: { [weak self] in
                    self?.isCurrent(songID: songID, generation: generation) == true
                }
            )
            guard let applyOutcome else {
                guard isCurrent(songID: songID, generation: generation) else { return }
                registerRequest(songID: songID, startsNewVisit: false)
                return
            }
            if let sessionRecorder {
                let recorderStatus = await sessionRecorder.bindIdentity(prepared.identity)
                guard isCurrent(songID: songID, generation: generation) else { return }
                guard recorderStatus.permitsExit else {
                    await publishRecorderFailure(songID: songID, status: recorderStatus)
                    return
                }
            }

            let metadata = SongScorePracticeMetadata(
                songID: songID,
                scoreFileVersionID: resolved.entry.scoreFileVersionID,
                scoreRevision: prepared.identity.scoreRevision,
                totalSourceMeasureCount: Set(prepared.measureSpans.map(\.sourceMeasureID)).count,
                preparedAt: now()
            )
            guard isCurrent(songID: songID, generation: generation) else {
                if accessFailure == nil {
                    scheduleMetadataWrite(metadata)
                }
                return
            }

            progressAccessFailure = accessFailure
            state = .ready(prepared.identity)
            if accessFailure == nil {
                scheduleMetadataWrite(metadata)
            }
            _ = await diagnosticsReporter.record(
                DiagnosticEvent(
                    severity: .info,
                    code: .practicePreparationSucceeded,
                    category: .practicePreparation,
                    stage: "practiceLaunchActivation",
                    summary: "曲谱练习数据已准备完成",
                    reason: "Prepared \(prepared.steps.count) steps and \(prepared.measureSpans.count) measure occurrences.",
                    songID: songID,
                    scoreRevision: prepared.identity.scoreRevision,
                    file: fileReference,
                    persistence: .exportable
                )
            )
            switch applyOutcome {
            case .applied:
                break
            case .appliedWithRepairedSavedState:
                _ = await diagnosticsReporter.record(
                    DiagnosticEvent(
                        severity: .warning,
                        code: .practiceSavedConfigurationRepaired,
                        category: .practiceSession,
                        stage: "practiceProgressRestore",
                        summary: "已修复无效的练习恢复位置",
                        reason: "invalidExactConfiguration: saved passage or resume data was replaced with a valid full-score state.",
                        songID: songID,
                        scoreRevision: prepared.identity.scoreRevision,
                        persistence: .exportable
                    )
                )
            case .appliedWithUnpersistedRepair:
                _ = await diagnosticsReporter.record(
                    DiagnosticEvent(
                        severity: .warning,
                        code: .practiceSavedConfigurationRepairFailed,
                        category: .practiceSession,
                        stage: "practiceProgressRestore",
                        summary: "无法保存练习恢复位置修复",
                        reason: "invalidExactConfiguration: the safe in-memory repair could not be persisted and may need repair again on the next launch.",
                        songID: songID,
                        scoreRevision: prepared.identity.scoreRevision,
                        persistence: .exportable
                    )
                )
            }
        } catch is CancellationError {
            return
        } catch {
            guard isCurrent(songID: songID, generation: generation) else { return }
            let preparationError: PracticePreparationError
            if let resolutionError = error as? SongLibraryEntryResolutionError {
                preparationError = resolutionError.preparationError
                fileReference = resolutionError.diagnosticFileReference
            } else {
                preparationError = (error as? PracticePreparationError) ?? .unexpected(
                    stage: "practiceLaunchActivation",
                    reason: PracticePreparationErrorDetails.safeErrorSummary(error)
                )
            }
            let failure = PracticeLaunchFailure.map(
                preparationError,
                entryID: songID,
                file: fileReference
            )
            state = .failure(failure)
            _ = await diagnosticsReporter.record(
                PianoPerformanceDiagnosticSample(
                    stage: .preparation,
                    outcome: .failed,
                    capability: .scoreParsing
                ).diagnosticEvent
            )
            _ = await diagnosticsReporter.record(failure.diagnosticEvent)
        }
    }

    private func isCurrent(songID: UUID, generation: Int) -> Bool {
        self.generation == generation &&
            requestedSongID == songID &&
            Task.isCancelled == false
    }

    private func isCurrentRecovery(songID: UUID, generation: Int) -> Bool {
        self.generation == generation && requestedSongID == songID
    }

    private func publishRecorderFailure(
        songID: UUID,
        status: PracticeSessionRecorderSaveStatus
    ) async {
        let failure = PracticeLaunchFailure.progressSaveFailed(entryID: songID)
        state = .failure(failure)
        _ = await diagnosticsReporter.record(
            DiagnosticEvent(
                severity: .error,
                code: .practiceProgressSaveFailed,
                category: .persistence,
                stage: "practiceSessionRecorder",
                summary: "无法准备练习会话记录",
                reason: "recorder=\(status.diagnosticToken)",
                songID: songID,
                persistence: .exportable
            )
        )
    }

    private func scheduleMetadataWrite(_ metadata: SongScorePracticeMetadata) {
        let operationID = UUID()
        let repository = progressRepository
        let reporter = diagnosticsReporter
        metadataWriteTasks[operationID] = Task { @MainActor [weak self] in
            do {
                try await repository.upsert(metadata)
            } catch {
                _ = await reporter.record(
                    DiagnosticEvent(
                        severity: .warning,
                        code: .practiceScoreMetadataWriteFailed,
                        category: .persistence,
                        stage: "practiceScoreMetadataWrite",
                        summary: "无法保存曲谱练习元数据",
                        reason: "token=\(metadata.scoreFileVersionID.uuidString); measureCount=\(metadata.totalSourceMeasureCount); \(PracticePreparationErrorDetails.safeErrorSummary(error))",
                        songID: metadata.songID,
                        scoreRevision: metadata.scoreRevision,
                        persistence: .exportable
                    )
                )
            }
            self?.metadataWriteTasks[operationID] = nil
        }
    }

    private func waitForMetadataWrites() async {
        while let task = metadataWriteTasks.values.first {
            await task.value
        }
    }

    private func retireCurrentActivationTask() {
        guard let activationTask else { return }
        activationTask.cancel()
        retiredActivationTasks.append(activationTask)
        self.activationTask = nil
    }

    private func settleRetiredActivationTasks() async {
        let tasks = retiredActivationTasks
        retiredActivationTasks.removeAll()
        for task in tasks {
            await task.value
        }
    }

    private func cancelAndWaitForMetadataWrites() async {
        let tasks = Array(metadataWriteTasks.values)
        tasks.forEach { $0.cancel() }
        for task in tasks {
            await task.value
        }
    }

    private func reportRecoveredSessions(in history: PracticeSongHistory) async {
        let recoveredSessions = history.sessions.filter {
            $0.termination == .recoveredAfterInterruption &&
                reportedRecoveredSessionIDs.insert($0.id).inserted
        }
        for session in recoveredSessions {
            _ = await diagnosticsReporter.record(
                DiagnosticEvent(
                    severity: .warning,
                    code: .practiceSessionRecovered,
                    category: .practiceSession,
                    stage: "practiceSessionRecovery",
                    summary: "已结算中断的练习会话",
                    reason: "An open session was finalized at its last persisted checkpoint.",
                    songID: session.songID,
                    scoreRevision: session.scoreRevision,
                    persistence: .systemOnly
                )
            )
        }
    }
}
