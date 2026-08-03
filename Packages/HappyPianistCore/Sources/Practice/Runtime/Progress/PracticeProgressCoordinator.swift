import Foundation
import Diagnostics

public protocol PracticeProgressClockProtocol: Sendable {
    func now() -> Date
}

public struct SystemPracticeProgressClock: PracticeProgressClockProtocol {
    public init() {}

    public func now() -> Date {
        .now
    }
}

public enum PracticeProgressSaveStatus: Equatable, Sendable {
    case idle
    case loaded
    case pending
    case saved
    case failed(message: String)
}

public struct PracticeProgressSession: Equatable, Sendable {
    public let generation: Int
    public let progress: SongPracticeProgress?
    public let isCurrent: Bool

    public init(generation: Int, progress: SongPracticeProgress?, isCurrent: Bool) {
        self.generation = generation
        self.progress = progress
        self.isCurrent = isCurrent
    }
}

public struct PracticeProgressAssessmentID: Equatable, Hashable, Sendable {
    public let analyzerRoundGeneration: UInt64
    public let planID: ScorePerformancePlanID
    public let sourceGeneration: UInt64

    public init(analyzerRoundGeneration: UInt64, planID: ScorePerformancePlanID, sourceGeneration: UInt64) {
        self.analyzerRoundGeneration = analyzerRoundGeneration
        self.planID = planID
        self.sourceGeneration = sourceGeneration
    }
}

public actor PracticeProgressCoordinator {
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
    private var pendingRevision: UInt64 = 0

    public init(
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

    public func begin(identity: PracticeSongIdentity) async -> PracticeProgressSession {
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

    public func checkpoint(_ progress: SongPracticeProgress, generation: Int) {
        guard accepts(progress: progress, generation: generation) else { return }
        if let lastAcceptedUpdatedAt, progress.updatedAt < lastAcceptedUpdatedAt { return }
        var timestamped = progress
        timestamped.updatedAt = max(progress.updatedAt, clock.now())
        lastAcceptedUpdatedAt = timestamped.updatedAt
        pendingProgress = timestamped
        pendingRevision &+= 1
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

    public func claimAssessment(
        _ id: PracticeProgressAssessmentID,
        identity: PracticeSongIdentity,
        generation: Int
    ) -> Bool {
        guard generation == currentGeneration, identity == currentIdentity else { return false }
        return claimedAssessmentIDs.insert(id).inserted
    }

    @discardableResult
    public func flush(generation: Int) async -> PracticeProgressSaveStatus {
        guard generation == currentGeneration else { return saveStatus }
        delayedFlushTask?.cancel()
        delayedFlushTask = nil
        guard let progress = pendingProgress, accepts(progress: progress, generation: generation) else {
            return saveStatus
        }
        let revision = pendingRevision

        do {
            try await repository.upsert(progress)
            guard generation == currentGeneration else { return saveStatus }
            if pendingRevision == revision {
                pendingProgress = nil
                saveStatus = .saved
            } else {
                saveStatus = .pending
            }
        } catch {
            guard generation == currentGeneration else { return saveStatus }
            let failureStatus = PracticeProgressSaveStatus.failed(message: error.localizedDescription)
            saveStatus = pendingRevision == revision ? failureStatus : .pending
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
    public func finish(generation: Int) async -> PracticeProgressSaveStatus {
        var status = await flush(generation: generation)
        guard generation == currentGeneration else { return status }
        while pendingProgress != nil {
            if case .failed = status { return status }
            status = await flush(generation: generation)
            guard generation == currentGeneration else { return status }
        }
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

    public func discardPendingProgress(generation: Int) {
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
