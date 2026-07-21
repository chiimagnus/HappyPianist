import Foundation

protocol PracticeProgressClockProtocol: Sendable {
    func now() -> Date
}

struct SystemPracticeProgressClock: PracticeProgressClockProtocol {
    func now() -> Date {
        .now
    }
}

enum PracticeProgressSaveStatus: Equatable {
    case idle
    case loaded
    case pending
    case saved
    case failed(message: String)
}

struct PracticeProgressSession: Equatable {
    let generation: Int
    let progress: SongPracticeProgress?
    let isCurrent: Bool
}

struct PracticeProgressAssessmentID: Equatable, Hashable, Sendable {
    let analyzerRoundGeneration: UInt64
    let planID: ScorePerformancePlanID
    let sourceGeneration: UInt64
}

actor PracticeProgressCoordinator {
    private let repository: any PracticeProgressRepositoryProtocol
    private let clock: any PracticeProgressClockProtocol
    private let checkpointDelay: Duration
    private let diagnosticsReporter: (any DiagnosticsReporting)?

    private var currentGeneration = 0
    private var currentIdentity: PracticeSongIdentity?
    private var pendingProgress: SongPracticeProgress?
    private var delayedFlushTask: Task<Void, Never>?
    private var saveStatus: PracticeProgressSaveStatus = .idle
    private var lastAcceptedUpdatedAt: Date?
    private var claimedAssessmentIDs: Set<PracticeProgressAssessmentID> = []

    init(
        repository: any PracticeProgressRepositoryProtocol,
        clock: any PracticeProgressClockProtocol = SystemPracticeProgressClock(),
        checkpointDelay: Duration = .milliseconds(350),
        diagnosticsReporter: (any DiagnosticsReporting)? = nil
    ) {
        self.repository = repository
        self.clock = clock
        self.checkpointDelay = checkpointDelay
        self.diagnosticsReporter = diagnosticsReporter
    }

    func begin(identity: PracticeSongIdentity) async -> PracticeProgressSession {
        delayedFlushTask?.cancel()
        delayedFlushTask = nil
        pendingProgress = nil
        claimedAssessmentIDs.removeAll(keepingCapacity: true)
        currentGeneration += 1
        currentIdentity = identity
        let generation = currentGeneration

        let progress = await repository.progress(for: identity)
        guard generation == currentGeneration, identity == currentIdentity else {
            return PracticeProgressSession(generation: generation, progress: nil, isCurrent: false)
        }
        lastAcceptedUpdatedAt = progress?.updatedAt
        saveStatus = .loaded
        return PracticeProgressSession(generation: generation, progress: progress, isCurrent: true)
    }

    func checkpoint(_ progress: SongPracticeProgress, generation: Int) {
        guard accepts(progress: progress, generation: generation) else { return }
        if let lastAcceptedUpdatedAt, progress.updatedAt < lastAcceptedUpdatedAt {
            return
        }
        var timestamped = progress
        timestamped.updatedAt = max(progress.updatedAt, clock.now())
        lastAcceptedUpdatedAt = timestamped.updatedAt
        pendingProgress = timestamped
        saveStatus = .pending

        delayedFlushTask?.cancel()
        delayedFlushTask = Task { [checkpointDelay] in
            do {
                try await Task.sleep(for: checkpointDelay)
            } catch {
                return
            }
            await self.flush(generation: generation)
        }
    }

    func claimAssessment(
        _ id: PracticeProgressAssessmentID,
        identity: PracticeSongIdentity,
        generation: Int
    ) -> Bool {
        guard generation == currentGeneration, identity == currentIdentity else { return false }
        return claimedAssessmentIDs.insert(id).inserted
    }

    @discardableResult
    func flush(generation: Int) async -> PracticeProgressSaveStatus {
        guard generation == currentGeneration else { return saveStatus }
        delayedFlushTask?.cancel()
        delayedFlushTask = nil
        guard let progress = pendingProgress, accepts(progress: progress, generation: generation) else {
            return saveStatus
        }

        do {
            try await repository.upsert(progress)
            guard generation == currentGeneration else { return saveStatus }
            pendingProgress = nil
            saveStatus = .saved
        } catch {
            guard generation == currentGeneration else { return saveStatus }
            let message = error.localizedDescription
            let failureStatus = PracticeProgressSaveStatus.failed(message: message)
            saveStatus = failureStatus
            if let diagnosticsReporter {
                _ = await diagnosticsReporter.record(
                    DiagnosticEvent(
                        severity: .warning,
                        code: .practiceProgressSaveFailed,
                        category: .persistence,
                        stage: "practiceProgressCheckpoint",
                        summary: "无法保存练习进度 checkpoint",
                        reason: PracticePreparationErrorDetails.safeErrorSummary(error),
                        songID: currentIdentity?.songID,
                        scoreRevision: currentIdentity?.scoreRevision,
                        persistence: .exportable
                    )
                )
            }
            return failureStatus
        }
        return saveStatus
    }

    @discardableResult
    func finish(generation: Int) async -> PracticeProgressSaveStatus {
        let status = await flush(generation: generation)
        guard generation == currentGeneration else { return status }
        if case .failed = status { return status }
        delayedFlushTask?.cancel()
        delayedFlushTask = nil
        currentIdentity = nil
        pendingProgress = nil
        lastAcceptedUpdatedAt = nil
        claimedAssessmentIDs.removeAll(keepingCapacity: true)
        currentGeneration += 1
        return status
    }

    func discardPendingProgress(generation: Int) {
        guard generation == currentGeneration else { return }
        delayedFlushTask?.cancel()
        delayedFlushTask = nil
        currentIdentity = nil
        pendingProgress = nil
        lastAcceptedUpdatedAt = nil
        claimedAssessmentIDs.removeAll(keepingCapacity: true)
        saveStatus = .idle
        currentGeneration += 1
    }

    private func accepts(progress: SongPracticeProgress, generation: Int) -> Bool {
        generation == currentGeneration && progress.identity == currentIdentity
    }
}
