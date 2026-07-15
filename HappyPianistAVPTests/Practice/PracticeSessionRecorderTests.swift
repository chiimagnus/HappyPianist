import Foundation
import Synchronization
@testable import HappyPianistAVP
import Testing

private enum RecorderRepositoryError: Error {
    case writeFailed
}

private actor RecorderRepository: PracticeSessionRepositoryProtocol {
    private var failuresRemaining = 0
    private var savedRecords: [PracticeSessionRecord] = []
    private var abandonedSessionIDs: [UUID] = []

    func upsert(_ session: PracticeSessionRecord) throws {
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw RecorderRepositoryError.writeFailed
        }
        savedRecords.append(session)
    }

    func failNextWrites(_ count: Int) {
        failuresRemaining = max(0, count)
    }

    func abandonLiveSession(id: UUID) {
        abandonedSessionIDs.append(id)
    }

    func records() -> [PracticeSessionRecord] {
        savedRecords
    }

    func abandonedIDs() -> [UUID] {
        abandonedSessionIDs
    }
}

private final class RecorderClock: Sendable {
    private struct State {
        var monotonicMilliseconds: Int64 = 0
        var wallDate = Date(timeIntervalSince1970: 1_000)
    }

    private let state = Mutex(State())
    let practiceDay: PracticeLocalDay

    init() throws {
        practiceDay = try #require(PracticeLocalDay(
            year: 2026,
            month: 7,
            day: 15,
            timeZoneIdentifier: "Asia/Singapore"
        ))
    }

    func advance(milliseconds: Int64) {
        state.withLock { state in
            state.monotonicMilliseconds += milliseconds
            state.wallDate.addTimeInterval(Double(milliseconds) / 1_000)
        }
    }

    func jumpWallTime(seconds: TimeInterval) {
        state.withLock { state in
            state.wallDate.addTimeInterval(seconds)
        }
    }

    func makeClock() -> PracticeSessionRecorderClock {
        PracticeSessionRecorderClock(
            monotonicMilliseconds: { [self] in
                state.withLock(\.monotonicMilliseconds)
            },
            wallDate: { [self] in
                state.withLock(\.wallDate)
            },
            localDay: { [practiceDay] _ in practiceDay }
        )
    }
}

private actor RecorderSleeper: SleeperProtocol {
    private var continuations: [CheckedContinuation<Void, Error>] = []
    private var durations: [Duration] = []

    func sleep(for duration: Duration) async throws {
        durations.append(duration)
        try await withCheckedThrowingContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func recordedDurations() -> [Duration] {
        durations
    }

    func resumeOldest() {
        guard continuations.isEmpty == false else { return }
        continuations.removeFirst().resume()
    }
}

private func makeRecorder(
    repository: RecorderRepository,
    clock: RecorderClock,
    sleeper: RecorderSleeper = RecorderSleeper(),
    diagnosticsReporter: (any DiagnosticsReporting)? = nil
) -> PracticeSessionRecorder {
    PracticeSessionRecorder(
        repository: repository,
        clock: clock.makeClock(),
        sleeper: sleeper,
        diagnosticsReporter: diagnosticsReporter
    )
}

@Test
func recorderReportsLifecycleWithoutExportingSessionContents() async throws {
    let repository = RecorderRepository()
    let clock = try RecorderClock()
    let reporter = InMemoryDiagnosticsReporter()
    let recorder = makeRecorder(
        repository: repository,
        clock: clock,
        diagnosticsReporter: reporter
    )
    await beginActiveVisit(recorder: recorder)

    await recorder.setGuiding(true)
    await repository.failNextWrites(1)
    await recorder.setSettingsPresented(true)
    await recorder.finalize()

    let events = await reporter.events
    #expect(events.map(\.code) == [
        .practiceSessionCreated,
        .practiceSessionCheckpointFailed,
        .practiceSessionFinalized,
    ])
    #expect(events.allSatisfy { $0.reason.contains("{") == false })
}

private func beginActiveVisit(
    recorder: PracticeSessionRecorder,
    visitID: UUID = UUID(),
    songID: UUID = UUID()
) async {
    await recorder.beginVisit(
        id: visitID,
        songID: songID,
        sceneIsActive: true
    )
    await recorder.bindIdentity(
        PracticeSongIdentity(songID: songID, scoreRevision: "revision")
    )
}

private func waitForSleep(
    _ expectedCount: Int,
    sleeper: RecorderSleeper
) async {
    for _ in 0 ..< 100 {
        if await sleeper.recordedDurations().count >= expectedCount {
            return
        }
        await Task.yield()
    }
}

private func waitForRecords(
    _ expectedCount: Int,
    repository: RecorderRepository
) async {
    for _ in 0 ..< 100 {
        if await repository.records().count >= expectedCount {
            return
        }
        await Task.yield()
    }
}

@Test
func recorderDoesNotCreateSessionWithoutGuiding() async throws {
    let repository = RecorderRepository()
    let clock = try RecorderClock()
    let recorder = makeRecorder(repository: repository, clock: clock)

    await beginActiveVisit(recorder: recorder)
    clock.advance(milliseconds: 10_000)
    #expect(await recorder.finalize() == .idle)
    #expect(await repository.records().isEmpty)
}

@Test
func recorderUsesOneSessionAcrossRoundsAndCountsOnlyEligibleDurations() async throws {
    let repository = RecorderRepository()
    let clock = try RecorderClock()
    let recorder = makeRecorder(repository: repository, clock: clock)
    let visitID = UUID()
    let songID = UUID()

    await beginActiveVisit(recorder: recorder, visitID: visitID, songID: songID)
    clock.advance(milliseconds: 5_000)
    await recorder.setGuiding(true)
    clock.advance(milliseconds: 10_000)
    await recorder.setGuiding(false)
    await recorder.setGuiding(true)
    clock.advance(milliseconds: 2_000)
    await recorder.setSettingsPresented(true)
    clock.advance(milliseconds: 3_000)
    await recorder.setSettingsPresented(false)
    clock.advance(milliseconds: 4_000)
    await recorder.setSceneActive(false)
    clock.advance(milliseconds: 100_000)
    await recorder.setSceneActive(true)
    clock.advance(milliseconds: 1_000)
    #expect(await recorder.finalize() == .saved)

    let records = await repository.records()
    let final = try #require(records.last)
    #expect(Set(records.map(\.id)) == [visitID])
    #expect(final.songID == songID)
    #expect(final.practiceWindowDurationMilliseconds == 25_000)
    #expect(final.activePracticeDurationMilliseconds == 17_000)
    #expect(final.termination == .normal)
    #expect(final.endedAt != nil)

    let countAfterFinalize = records.count
    clock.advance(milliseconds: 10_000)
    #expect(await recorder.finalize() == .saved)
    #expect(await repository.records().count == countAfterFinalize)
}

@Test
func recorderPeriodicCheckpointUsesThirtySecondCadence() async throws {
    let repository = RecorderRepository()
    let clock = try RecorderClock()
    let sleeper = RecorderSleeper()
    let recorder = makeRecorder(repository: repository, clock: clock, sleeper: sleeper)

    await beginActiveVisit(recorder: recorder)
    await recorder.setGuiding(true)
    await waitForSleep(1, sleeper: sleeper)
    #expect(await sleeper.recordedDurations() == [.seconds(30)])

    clock.advance(milliseconds: 30_000)
    await sleeper.resumeOldest()
    await waitForRecords(2, repository: repository)
    let periodic = try #require(await repository.records().last)
    #expect(periodic.practiceWindowDurationMilliseconds == 30_000)
    #expect(periodic.activePracticeDurationMilliseconds == 30_000)
}

@Test
func recorderRetriesFailedWriteAtNextBoundary() async throws {
    let repository = RecorderRepository()
    await repository.failNextWrites(1)
    let clock = try RecorderClock()
    let recorder = makeRecorder(repository: repository, clock: clock)

    await beginActiveVisit(recorder: recorder)
    clock.advance(milliseconds: 1_000)
    guard case .failed = await recorder.setGuiding(true) else {
        Issue.record("Expected the first session write to remain pending")
        return
    }
    #expect(await repository.records().isEmpty)

    clock.advance(milliseconds: 1_000)
    #expect(await recorder.setSettingsPresented(true) == .saved)
    let retried = try #require(await repository.records().last)
    #expect(retried.practiceWindowDurationMilliseconds == 2_000)
    #expect(retried.activePracticeDurationMilliseconds == 1_000)
}

@Test
func recorderDiscardKeepsLastSuccessfulCheckpoint() async throws {
    let repository = RecorderRepository()
    let clock = try RecorderClock()
    let recorder = makeRecorder(repository: repository, clock: clock)
    let visitID = UUID()

    await beginActiveVisit(recorder: recorder, visitID: visitID)
    clock.advance(milliseconds: 1_000)
    await recorder.setGuiding(true)
    let saved = try #require(await repository.records().last)
    await repository.failNextWrites(1)

    clock.advance(milliseconds: 1_000)
    guard case .failed = await recorder.setSettingsPresented(true) else {
        Issue.record("Expected an unsaved delta")
        return
    }
    await recorder.discardPendingDelta()

    #expect(await repository.records() == [saved])
    #expect(await repository.abandonedIDs() == [visitID])
    #expect(await recorder.finalize() == .idle)
}

@Test
func recorderDurationIgnoresWallClockChanges() async throws {
    let repository = RecorderRepository()
    let clock = try RecorderClock()
    let recorder = makeRecorder(repository: repository, clock: clock)

    await beginActiveVisit(recorder: recorder)
    await recorder.setGuiding(true)
    clock.jumpWallTime(seconds: 86_400)
    await recorder.checkpoint()
    var latest = try #require(await repository.records().last)
    #expect(latest.practiceWindowDurationMilliseconds == 0)
    #expect(latest.activePracticeDurationMilliseconds == 0)

    clock.advance(milliseconds: 1_000)
    await recorder.finalize()
    latest = try #require(await repository.records().last)
    #expect(latest.practiceWindowDurationMilliseconds == 1_000)
    #expect(latest.activePracticeDurationMilliseconds == 1_000)
}

@Test
func recorderIgnoresCancelledPeriodicCheckpointThatFinishesLate() async throws {
    let repository = RecorderRepository()
    let clock = try RecorderClock()
    let sleeper = RecorderSleeper()
    let recorder = makeRecorder(repository: repository, clock: clock, sleeper: sleeper)

    await beginActiveVisit(recorder: recorder)
    await recorder.setGuiding(true)
    await waitForSleep(1, sleeper: sleeper)
    clock.advance(milliseconds: 5_000)
    await recorder.setSettingsPresented(true)
    let countAfterSettingsBoundary = await repository.records().count

    clock.advance(milliseconds: 30_000)
    await sleeper.resumeOldest()
    for _ in 0 ..< 20 { await Task.yield() }

    #expect(await repository.records().count == countAfterSettingsBoundary)
}
