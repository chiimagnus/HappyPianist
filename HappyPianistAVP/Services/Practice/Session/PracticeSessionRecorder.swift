import Foundation

struct PracticeSessionRecorderClock: Sendable {
    let monotonicMilliseconds: @Sendable () -> Int64
    let wallDate: @Sendable () -> Date
    let localDay: @Sendable (Date) -> PracticeLocalDay?

    static func live() -> Self {
        let clock = ContinuousClock()
        let origin = clock.now
        return Self(
            monotonicMilliseconds: {
                milliseconds(in: origin.duration(to: clock.now))
            },
            wallDate: { .now },
            localDay: { date in
                let timeZone = TimeZone.autoupdatingCurrent
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = timeZone
                let components = calendar.dateComponents([.year, .month, .day], from: date)
                guard let year = components.year,
                      let month = components.month,
                      let day = components.day
                else {
                    return nil
                }
                return PracticeLocalDay(
                    year: year,
                    month: month,
                    day: day,
                    timeZoneIdentifier: timeZone.identifier
                )
            }
        )
    }

    private static func milliseconds(in duration: Duration) -> Int64 {
        let components = duration.components
        guard components.seconds >= 0 else { return 0 }
        let (wholeMilliseconds, multipliedOverflow) = components.seconds.multipliedReportingOverflow(by: 1_000)
        guard multipliedOverflow == false else { return .max }
        let fractionalMilliseconds = max(0, components.attoseconds / 1_000_000_000_000_000)
        let (milliseconds, addedOverflow) = wholeMilliseconds.addingReportingOverflow(fractionalMilliseconds)
        return addedOverflow ? .max : milliseconds
    }
}

enum PracticeSessionRecorderSaveStatus: Equatable, Sendable {
    case idle
    case pending
    case saved
    case failed(description: String)

    var permitsExit: Bool {
        switch self {
        case .idle, .saved:
            true
        case .pending, .failed:
            false
        }
    }

    var diagnosticToken: String {
        switch self {
        case .idle:
            "idle"
        case .pending:
            "pending"
        case .saved:
            "saved"
        case .failed:
            "failed"
        }
    }
}

actor PracticeSessionRecorder {
    private struct VisitState {
        let id: UUID
        let songID: UUID
        let windowOpenedAt: Date
        var scoreRevision: String?
        var lastMonotonicMilliseconds: Int64
        var sceneIsActive: Bool
        var isGuiding = false
        var settingsArePresented = false
        var practiceStartedAt: Date?
        var practiceDay: PracticeLocalDay?
        var endedAt: Date?
        var windowDurationMilliseconds: Int64 = 0
        var activeDurationMilliseconds: Int64 = 0
        var isFinalized = false
        var didReportCreation = false
        var didReportFinalization = false
    }

    private let repository: any PracticeSessionRepositoryProtocol
    private let clock: PracticeSessionRecorderClock
    private let sleeper: any SleeperProtocol
    private let checkpointInterval: Duration
    private let diagnosticsReporter: (any DiagnosticsReporting)?

    private var visit: VisitState?
    private var pendingRecord: PracticeSessionRecord?
    private var saveStatus: PracticeSessionRecorderSaveStatus = .idle
    private var periodicCheckpointTask: Task<Void, Never>?
    private var periodicCheckpointGeneration = 0
    private var persistenceTask: Task<PracticeSessionRecorderSaveStatus, Never>?
    private var persistenceGeneration = 0
    private var didReportPendingFailure = false

    init(
        repository: any PracticeSessionRepositoryProtocol,
        clock: PracticeSessionRecorderClock = .live(),
        sleeper: any SleeperProtocol = TaskSleeper(),
        checkpointInterval: Duration = .seconds(30),
        diagnosticsReporter: (any DiagnosticsReporting)? = nil
    ) {
        self.repository = repository
        self.clock = clock
        self.sleeper = sleeper
        self.checkpointInterval = min(max(checkpointInterval, .milliseconds(1)), .seconds(30))
        self.diagnosticsReporter = diagnosticsReporter
    }

    @discardableResult
    func beginVisit(
        id: UUID,
        songID: UUID,
        sceneIsActive: Bool
    ) async -> PracticeSessionRecorderSaveStatus {
        if visit?.id == id {
            return saveStatus
        }
        if visit != nil {
            let previousStatus = await finalize()
            guard previousStatus.permitsExit else { return previousStatus }
        }

        cancelPeriodicCheckpoint()
        pendingRecord = nil
        saveStatus = .idle
        didReportPendingFailure = false
        visit = VisitState(
            id: id,
            songID: songID,
            windowOpenedAt: clock.wallDate(),
            scoreRevision: nil,
            lastMonotonicMilliseconds: max(0, clock.monotonicMilliseconds()),
            sceneIsActive: sceneIsActive
        )
        return .idle
    }

    @discardableResult
    func bindIdentity(_ identity: PracticeSongIdentity) -> PracticeSessionRecorderSaveStatus {
        guard var visit, visit.isFinalized == false else { return saveStatus }
        guard visit.songID == identity.songID else {
            saveStatus = .failed(description: "practice-visit-song-mismatch")
            return saveStatus
        }
        if let scoreRevision = visit.scoreRevision,
           scoreRevision != identity.scoreRevision {
            saveStatus = .failed(description: "practice-visit-revision-mismatch")
            return saveStatus
        }
        visit.scoreRevision = identity.scoreRevision
        self.visit = visit
        return saveStatus
    }

    @discardableResult
    func setSceneActive(_ isActive: Bool) async -> PracticeSessionRecorderSaveStatus {
        guard var visit, visit.isFinalized == false else { return saveStatus }
        guard visit.sceneIsActive != isActive else { return saveStatus }
        advance(&visit)
        visit.sceneIsActive = isActive
        self.visit = visit
        queueCurrentRecord()
        refreshPeriodicCheckpoint()
        return await flushPendingRecord()
    }

    @discardableResult
    func setGuiding(_ isGuiding: Bool) async -> PracticeSessionRecorderSaveStatus {
        guard var visit, visit.isFinalized == false else { return saveStatus }
        guard visit.isGuiding != isGuiding else { return saveStatus }
        advance(&visit)
        var firstCheckpointDate: Date?
        if isGuiding, visit.practiceStartedAt == nil {
            guard visit.scoreRevision != nil else {
                saveStatus = .failed(description: "practice-visit-revision-unavailable")
                self.visit = visit
                return saveStatus
            }
            let startedAt = clock.wallDate()
            guard let practiceDay = clock.localDay(startedAt) else {
                saveStatus = .failed(description: "invalid-local-practice-day")
                self.visit = visit
                return saveStatus
            }
            visit.practiceStartedAt = startedAt
            visit.practiceDay = practiceDay
            firstCheckpointDate = startedAt
        }
        visit.isGuiding = isGuiding

        self.visit = visit
        queueCurrentRecord(persistedAt: firstCheckpointDate)
        refreshPeriodicCheckpoint()
        return await flushPendingRecord()
    }

    @discardableResult
    func setSettingsPresented(_ isPresented: Bool) async -> PracticeSessionRecorderSaveStatus {
        guard var visit, visit.isFinalized == false else { return saveStatus }
        guard visit.settingsArePresented != isPresented else { return saveStatus }
        advance(&visit)
        visit.settingsArePresented = isPresented
        self.visit = visit
        queueCurrentRecord()
        refreshPeriodicCheckpoint()
        return await flushPendingRecord()
    }

    @discardableResult
    func checkpoint() async -> PracticeSessionRecorderSaveStatus {
        guard var visit, visit.isFinalized == false else { return saveStatus }
        advance(&visit)
        self.visit = visit
        queueCurrentRecord()
        return await flushPendingRecord()
    }

    @discardableResult
    func finalize() async -> PracticeSessionRecorderSaveStatus {
        guard var visit else { return saveStatus }
        if visit.isFinalized {
            return await flushPendingRecord()
        }

        cancelPeriodicCheckpoint()
        advance(&visit)
        visit.isFinalized = true
        guard visit.practiceStartedAt != nil else {
            self.visit = visit
            saveStatus = .idle
            return .idle
        }

        let endedAt = clock.wallDate()
        visit.endedAt = endedAt
        self.visit = visit
        queueCurrentRecord(persistedAt: endedAt)
        return await flushPendingRecord()
    }

    func discardPendingDelta() async {
        cancelPeriodicCheckpoint()
        let abandonedSessionID = visit?.practiceStartedAt == nil ? nil : visit?.id
        if let persistenceTask {
            _ = await persistenceTask.value
        }
        pendingRecord = nil
        visit = nil
        saveStatus = .idle
        didReportPendingFailure = false
        if let abandonedSessionID {
            await repository.abandonLiveSession(id: abandonedSessionID)
        }
    }

    private func advance(_ visit: inout VisitState) {
        let now = max(0, clock.monotonicMilliseconds())
        let delta = now >= visit.lastMonotonicMilliseconds
            ? now - visit.lastMonotonicMilliseconds
            : 0
        visit.lastMonotonicMilliseconds = now
        if visit.sceneIsActive {
            visit.windowDurationMilliseconds = addingWithoutOverflow(
                delta,
                to: visit.windowDurationMilliseconds
            )
            if visit.isGuiding, visit.settingsArePresented == false {
                visit.activeDurationMilliseconds = addingWithoutOverflow(
                    delta,
                    to: visit.activeDurationMilliseconds
                )
            }
        }
    }

    private func addingWithoutOverflow(_ value: Int64, to total: Int64) -> Int64 {
        let (result, overflow) = total.addingReportingOverflow(value)
        return overflow ? .max : result
    }

    private func queueCurrentRecord(persistedAt: Date? = nil) {
        guard let visit,
              let scoreRevision = visit.scoreRevision,
              let practiceStartedAt = visit.practiceStartedAt,
              let practiceDay = visit.practiceDay,
              let record = PracticeSessionRecord(
                id: visit.id,
                songID: visit.songID,
                scoreRevision: scoreRevision,
                windowOpenedAt: visit.windowOpenedAt,
                practiceStartedAt: practiceStartedAt,
                practiceDay: practiceDay,
                endedAt: visit.endedAt,
                lastPersistedAt: persistedAt ?? clock.wallDate(),
                practiceWindowDurationMilliseconds: visit.windowDurationMilliseconds,
                activePracticeDurationMilliseconds: visit.activeDurationMilliseconds,
                termination: visit.isFinalized ? .normal : .open
              )
        else {
            return
        }
        pendingRecord = record
        saveStatus = .pending
    }

    private func flushPendingRecord() async -> PracticeSessionRecorderSaveStatus {
        guard pendingRecord != nil else {
            await reportPersistenceStatus(saveStatus)
            return saveStatus
        }
        if let persistenceTask {
            let status = await persistenceTask.value
            await reportPersistenceStatus(status)
            return status
        }

        persistenceGeneration += 1
        let generation = persistenceGeneration
        let task = Task { await self.drainPendingRecords(generation: generation) }
        persistenceTask = task
        let status = await task.value
        await reportPersistenceStatus(status)
        return status
    }

    private func reportPersistenceStatus(_ status: PracticeSessionRecorderSaveStatus) async {
        guard let diagnosticsReporter, var visit else { return }
        switch status {
        case .saved:
            didReportPendingFailure = false
            var events: [DiagnosticEvent] = []
            if visit.practiceStartedAt != nil, visit.didReportCreation == false {
                visit.didReportCreation = true
                events.append(
                    DiagnosticEvent(
                        severity: .info,
                        code: .practiceSessionCreated,
                        category: .practiceSession,
                        stage: "practiceSessionRecorder",
                        summary: "练习会话已创建",
                        reason: "The visit entered guiding and its first session checkpoint was saved.",
                        songID: visit.songID,
                        scoreRevision: visit.scoreRevision,
                        persistence: .systemOnly
                    )
                )
            }
            if visit.isFinalized, visit.didReportFinalization == false {
                visit.didReportFinalization = true
                events.append(
                    DiagnosticEvent(
                        severity: .info,
                        code: .practiceSessionFinalized,
                        category: .practiceSession,
                        stage: "practiceSessionRecorder",
                        summary: "练习会话已正常结算",
                        reason: "The final session checkpoint was saved before leaving Practice.",
                        songID: visit.songID,
                        scoreRevision: visit.scoreRevision,
                        persistence: .systemOnly
                    )
                )
            }
            self.visit = visit
            for event in events {
                _ = await diagnosticsReporter.record(event)
            }
        case .failed:
            guard didReportPendingFailure == false else { return }
            didReportPendingFailure = true
            _ = await diagnosticsReporter.record(
                DiagnosticEvent(
                    severity: .warning,
                    code: .practiceSessionCheckpointFailed,
                    category: .persistence,
                    stage: "practiceSessionRecorder",
                    summary: "无法保存练习会话 checkpoint",
                    reason: "The recorder retained a pending checkpoint for the next lifecycle boundary.",
                    songID: visit.songID,
                    scoreRevision: visit.scoreRevision,
                    persistence: .exportable
                )
            )
        case .idle, .pending:
            break
        }
    }

    private func drainPendingRecords(
        generation: Int
    ) async -> PracticeSessionRecorderSaveStatus {
        var didSave = false
        while let record = pendingRecord {
            pendingRecord = nil
            do {
                try await repository.upsert(record)
                didSave = true
            } catch {
                if pendingRecord == nil {
                    pendingRecord = record
                }
                saveStatus = .failed(description: Self.safeDescription(error))
                clearPersistenceTask(generation: generation)
                return saveStatus
            }
        }
        saveStatus = didSave ? .saved : saveStatus
        clearPersistenceTask(generation: generation)
        return saveStatus
    }

    private func clearPersistenceTask(generation: Int) {
        guard generation == persistenceGeneration else { return }
        persistenceTask = nil
    }

    private func refreshPeriodicCheckpoint() {
        guard let visit,
              visit.isFinalized == false,
              visit.practiceStartedAt != nil,
              visit.sceneIsActive,
              visit.isGuiding,
              visit.settingsArePresented == false
        else {
            cancelPeriodicCheckpoint()
            return
        }
        guard periodicCheckpointTask == nil else { return }

        periodicCheckpointGeneration += 1
        let generation = periodicCheckpointGeneration
        let visitID = visit.id
        periodicCheckpointTask = Task { [checkpointInterval, sleeper] in
            do {
                try await sleeper.sleep(for: checkpointInterval)
            } catch {
                return
            }
            await self.periodicCheckpointFired(visitID: visitID, generation: generation)
        }
    }

    private func periodicCheckpointFired(visitID: UUID, generation: Int) async {
        guard generation == periodicCheckpointGeneration,
              visit?.id == visitID
        else {
            return
        }
        periodicCheckpointTask = nil
        _ = await checkpoint()
        guard generation == periodicCheckpointGeneration else { return }
        refreshPeriodicCheckpoint()
    }

    private func cancelPeriodicCheckpoint() {
        periodicCheckpointGeneration += 1
        periodicCheckpointTask?.cancel()
        periodicCheckpointTask = nil
    }

    private static func safeDescription(_ error: Error) -> String {
        let error = error as NSError
        return "\(error.domain)#\(error.code)"
    }
}
