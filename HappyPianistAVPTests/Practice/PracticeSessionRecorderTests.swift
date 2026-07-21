import Foundation
@testable import HappyPianistAVP
import Synchronization
import Testing

private enum RecorderRepositoryError: Error {
    case writeFailed
}

private actor RecorderRepository: PracticeSessionRepositoryProtocol {
    private var failuresRemaining = 0
    private var writeAttemptCount = 0
    private var savedRecords: [PracticeSessionRecord] = []
    private var abandonedSessionIDs: [UUID] = []

    func upsert(_ session: PracticeSessionRecord) throws {
        writeAttemptCount += 1
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

    func waitForWriteAttempts(_ count: Int) async {
        while writeAttemptCount < count {
            await Task.yield()
        }
    }
}

private final class RecorderClock: Sendable {
    private struct State {
        var monotonicMilliseconds: Int64 = 0
        var monotonicReadCount = 0
        var wallDate = Date(timeIntervalSince1970: 1000)
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
            state.wallDate.addTimeInterval(Double(milliseconds) / 1000)
        }
    }

    func jumpWallTime(seconds: TimeInterval) {
        state.withLock { state in
            state.wallDate.addTimeInterval(seconds)
        }
    }

    func waitForMonotonicReads(_ count: Int) async {
        while state.withLock({ $0.monotonicReadCount }) < count {
            await Task.yield()
        }
    }

    func makeClock() -> PracticeSessionRecorderClock {
        PracticeSessionRecorderClock(
            monotonic: PerformanceClock { [self] in
                state.withLock { state in
                    state.monotonicReadCount += 1
                    return PerformanceMonotonicInstant(milliseconds: state.monotonicMilliseconds)
                }
            },
            wallDate: { [self] in
                state.withLock(\.wallDate)
            },
            localDay: { [practiceDay] _ in practiceDay }
        )
    }
}

@Test
func performanceClockSynchronizerCalibratesOffsetLatencyAndDrift() throws {
    var synchronizer = PerformanceClockSynchronizer(maximumDriftRatio: 0.05)
    let first = synchronizer.reading(
        source: PerformanceSourceTimestamp(clockID: "midi", seconds: 10),
        receivedAt: PerformanceMonotonicInstant(seconds: 12.1),
        estimatedLatencySeconds: 0.1
    )
    let second = synchronizer.reading(
        source: PerformanceSourceTimestamp(clockID: "midi", seconds: 20),
        receivedAt: PerformanceMonotonicInstant(seconds: 22.2),
        estimatedLatencySeconds: 0.1
    )

    #expect(first.correctedHost.seconds == 12)
    #expect(second.mapping?.sampleCount == 2)
    #expect(second.mapping?.provenance == .offsetAndDriftSamples)
    #expect(try #require(second.mapping?.rate) > 1)
    #expect(abs(second.correctedHost.seconds - 22.1) < 0.000_001)
}

@Test
func performanceClockSynchronizerFallsBackToHostForUncalibratedSource() {
    var synchronizer = PerformanceClockSynchronizer()
    let reading = synchronizer.reading(
        source: nil,
        receivedAt: PerformanceMonotonicInstant(seconds: 3),
        estimatedLatencySeconds: 0.25
    )

    #expect(reading.mapping == nil)
    #expect(reading.provenance == .latencyEstimate)
    #expect(reading.correctedHost.seconds == 2.75)
}

@Test
func sessionRecorderKeepsRawObservationsInMemoryWithoutWritingProgressJSON() async throws {
    let repository = RecorderRepository()
    let clock = try RecorderClock()
    let recorder = makeRecorder(repository: repository, clock: clock)
    await beginActiveVisit(recorder: recorder)
    await recorder.setGuiding(true)
    let reading = PerformanceClockReading(
        host: PerformanceMonotonicInstant(seconds: 2),
        source: nil,
        correctedHost: PerformanceMonotonicInstant(seconds: 2),
        mapping: nil,
        provenance: .hostOnly
    )
    let source = PerformanceObservation.Source(kind: .midi1, id: "endpoint:1", generation: 1)

    await recorder.record(PerformanceObservation(
        source: source,
        timing: reading,
        event: .noteOn(note: 64, velocity: .init(midi1: 100))
    ))
    await recorder.record(PerformanceObservation(
        source: source,
        timing: reading,
        event: .noteOff(note: 64, releaseVelocity: .init(midi1: 40))
    ))
    _ = await recorder.checkpoint()

    let snapshot = await recorder.observationSnapshot()
    #expect(snapshot.map(\.event) == [
        .noteOn(note: 64, velocity: .init(midi1: 100)),
        .noteOff(note: 64, releaseVelocity: .init(midi1: 40)),
    ])
    let progressRecord = try #require(await repository.records().last)
    let data = try JSONEncoder().encode(progressRecord)
    #expect(String(decoding: data, as: UTF8.self).contains("endpoint:1") == false)
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
    diagnosticsReporter: (any DiagnosticsReporting)? = nil,
    performanceAnalyzer: PracticePerformanceAnalyzer? = nil
) -> PracticeSessionRecorder {
    PracticeSessionRecorder(
        repository: repository,
        clock: clock.makeClock(),
        sleeper: sleeper,
        diagnosticsReporter: diagnosticsReporter,
        performanceAnalyzer: performanceAnalyzer
    )
}

@Test
func recorderFeedsConfiguredPlanAndObservationsToTransientAnalyzer() async throws {
    let repository = RecorderRepository()
    let clock = try RecorderClock()
    let reporter = InMemoryDiagnosticsReporter()
    let analyzer = PracticePerformanceAnalyzer(diagnosticsReporter: reporter)
    let recorder = makeRecorder(
        repository: repository,
        clock: clock,
        performanceAnalyzer: analyzer
    )
    let plan = makeTestScorePerformancePlan(notes: [
        TestScorePerformanceNote(midiNote: 60, onTick: 0, offTick: 480),
    ])
    await beginActiveVisit(recorder: recorder, songID: plan.sourceScoreIdentity.songID)
    await recorder.configureAnalysis(plan: plan, activeTickRange: nil)
    await recorder.setGuiding(true)
    let source = PerformanceObservation.Source(kind: .midi1, id: "midi:test", generation: 7)
    let secondSource = PerformanceObservation.Source(kind: .midi2, id: "midi:second", generation: 2)
    let instant = PerformanceMonotonicInstant(seconds: 0)
    await recorder.record(PerformanceObservation(
        source: source,
        timing: .init(
            host: instant,
            source: nil,
            correctedHost: instant,
            mapping: nil,
            provenance: .hostOnly
        ),
        event: .noteOn(note: 60, velocity: .init(midi1: 90))
    ))
    await recorder.record(PerformanceObservation(
        source: secondSource,
        timing: .init(
            host: .init(seconds: 0.1),
            source: nil,
            correctedHost: .init(seconds: 0.1),
            mapping: nil,
            provenance: .hostOnly
        ),
        event: .noteOn(note: 60, velocity: .init(midi2: 40_000))
    ))
    await recorder.record(PerformanceObservation(
        source: .init(kind: .midi1, id: "midi:test", generation: 6),
        timing: .init(
            host: .init(seconds: 0.2),
            source: nil,
            correctedHost: .init(seconds: 0.2),
            mapping: nil,
            provenance: .hostOnly
        ),
        event: .noteOn(note: 60, velocity: .init(midi1: 90))
    ))
    _ = await recorder.finalize()

    let snapshot = try #require(await recorder.analysisSnapshot())
    #expect(snapshot.roundGeneration == 1)
    #expect(snapshot.acceptedObservationCount == 2)
    #expect(snapshot.rejectedObservationCount == 1)
    #expect(snapshot.discardedObservationCount == 0)
    #expect(snapshot.alignmentLatencyMilliseconds != nil)
    #expect(snapshot.isRunning == false)
    #expect(snapshot.alignment?.links.contains { if case .aligned = $0 { true } else { false } } == true)
    let data = try JSONEncoder().encode(try #require(await repository.records().last))
    #expect(String(decoding: data, as: UTF8.self).contains("alignment") == false)
    let diagnostic = try #require(await reporter.events.first { $0.stage == "performanceAlignment" })
    for token in ["discarded=", "latencyMs=", "candidates=", "aligned=", "missing=", "extra="] {
        #expect(diagnostic.reason.contains(token))
    }
}

@Test
func recorderStartsANewAnalyzerGenerationForEachGuidingRound() async throws {
    let repository = RecorderRepository()
    let clock = try RecorderClock()
    let recorder = makeRecorder(
        repository: repository,
        clock: clock,
        performanceAnalyzer: PracticePerformanceAnalyzer()
    )
    let plan = makeTestScorePerformancePlan(notes: [
        TestScorePerformanceNote(midiNote: 60, onTick: 0, offTick: 480),
    ])
    await beginActiveVisit(recorder: recorder, songID: plan.sourceScoreIdentity.songID)
    await recorder.configureAnalysis(plan: plan, activeTickRange: nil)
    let source = PerformanceObservation.Source(kind: .midi1, id: "midi:test", generation: 1)

    await recorder.setGuiding(true)
    await recorder.record(.init(
        source: source,
        timing: .init(
            host: .init(seconds: 0),
            source: nil,
            correctedHost: .init(seconds: 0),
            mapping: nil,
            provenance: .hostOnly
        ),
        event: .noteOn(note: 60, velocity: .init(midi1: 90))
    ))
    await recorder.setGuiding(false)
    let first = try #require(await recorder.analysisSnapshot())

    clock.advance(milliseconds: 1_000)
    await recorder.setGuiding(true)
    await recorder.record(.init(
        source: source,
        timing: .init(
            host: .init(seconds: 1),
            source: nil,
            correctedHost: .init(seconds: 1),
            mapping: nil,
            provenance: .hostOnly
        ),
        event: .noteOn(note: 60, velocity: .init(midi1: 90))
    ))
    await recorder.setGuiding(false)
    let second = try #require(await recorder.analysisSnapshot())

    #expect(first.roundGeneration == 1)
    #expect(first.acceptedObservationCount == 1)
    #expect(second.roundGeneration == 2)
    #expect(second.acceptedObservationCount == 1)
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
    _ = await recorder.checkpoint()
    await repository.failNextWrites(1)
    await recorder.setSettingsPresented(true)
    await repository.waitForWriteAttempts(3)
    for _ in 0 ..< 10 {
        await Task.yield()
    }
    _ = await recorder.checkpoint()
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
    clock.advance(milliseconds: 10000)
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
    clock.advance(milliseconds: 5000)
    await recorder.setGuiding(true)
    clock.advance(milliseconds: 10000)
    await recorder.setGuiding(false)
    await recorder.setGuiding(true)
    clock.advance(milliseconds: 2000)
    await recorder.setSettingsPresented(true)
    clock.advance(milliseconds: 3000)
    await recorder.setSettingsPresented(false)
    clock.advance(milliseconds: 4000)
    await recorder.setSceneActive(false)
    clock.advance(milliseconds: 100_000)
    await recorder.setSceneActive(true)
    clock.advance(milliseconds: 1000)
    #expect(await recorder.finalize() == .saved)

    let records = await repository.records()
    let final = try #require(records.last)
    #expect(Set(records.map(\.id)) == [visitID])
    #expect(final.songID == songID)
    #expect(final.practiceWindowDurationMilliseconds == 25000)
    #expect(final.activePracticeDurationMilliseconds == 17000)
    #expect(final.termination == .normal)
    #expect(final.endedAt != nil)

    let countAfterFinalize = records.count
    clock.advance(milliseconds: 10000)
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

    clock.advance(milliseconds: 30000)
    await sleeper.resumeOldest()
    await waitForRecords(2, repository: repository)
    let periodic = try #require(await repository.records().last)
    #expect(periodic.practiceWindowDurationMilliseconds == 30000)
    #expect(periodic.activePracticeDurationMilliseconds == 30000)
}

@Test
func recorderRetriesFailedWriteAtNextBoundary() async throws {
    let repository = RecorderRepository()
    await repository.failNextWrites(1)
    let clock = try RecorderClock()
    let recorder = makeRecorder(repository: repository, clock: clock)

    await beginActiveVisit(recorder: recorder)
    clock.advance(milliseconds: 1000)
    await recorder.setGuiding(true)
    await repository.waitForWriteAttempts(1)
    for _ in 0 ..< 10 {
        await Task.yield()
    }
    #expect(await repository.records().isEmpty)

    clock.advance(milliseconds: 1000)
    await recorder.setSettingsPresented(true)
    #expect(await recorder.checkpoint() == .saved)
    let retried = try #require(await repository.records().last)
    #expect(retried.practiceWindowDurationMilliseconds == 2000)
    #expect(retried.activePracticeDurationMilliseconds == 1000)
}

@Test
func recorderDiscardKeepsLastSuccessfulCheckpoint() async throws {
    let repository = RecorderRepository()
    let clock = try RecorderClock()
    let recorder = makeRecorder(repository: repository, clock: clock)
    let visitID = UUID()

    await beginActiveVisit(recorder: recorder, visitID: visitID)
    clock.advance(milliseconds: 1000)
    await recorder.setGuiding(true)
    _ = await recorder.checkpoint()
    let savedRecords = await repository.records()
    _ = try #require(savedRecords.last)
    await repository.failNextWrites(1)

    clock.advance(milliseconds: 1000)
    await recorder.setSettingsPresented(true)
    await repository.waitForWriteAttempts(3)
    for _ in 0 ..< 10 {
        await Task.yield()
    }
    await recorder.discardPendingDelta()

    #expect(await repository.records() == savedRecords)
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
    clock.jumpWallTime(seconds: 86400)
    await recorder.checkpoint()
    var latest = try #require(await repository.records().last)
    #expect(latest.practiceWindowDurationMilliseconds == 0)
    #expect(latest.activePracticeDurationMilliseconds == 0)

    clock.advance(milliseconds: 1000)
    await recorder.finalize()
    latest = try #require(await repository.records().last)
    #expect(latest.practiceWindowDurationMilliseconds == 1000)
    #expect(latest.activePracticeDurationMilliseconds == 1000)
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
    clock.advance(milliseconds: 5000)
    await recorder.setSettingsPresented(true)
    _ = await recorder.checkpoint()
    let countAfterSettingsBoundary = await repository.records().count

    clock.advance(milliseconds: 30000)
    await sleeper.resumeOldest()
    for _ in 0 ..< 20 {
        await Task.yield()
    }

    #expect(await repository.records().count == countAfterSettingsBoundary)
}

@Test
func recorderFinalizeUsesBoundaryAfterBlockedPersistenceAndInterleavedEvent() async throws {
    let repository = GatedRecorderRepository()
    let clock = try RecorderClock()
    let recorder = PracticeSessionRecorder(
        repository: repository,
        clock: clock.makeClock(),
        sleeper: RecorderSleeper()
    )
    await beginActiveVisit(recorder: recorder)
    await recorder.setGuiding(true)
    await repository.waitUntilFirstWriteStarts()

    clock.advance(milliseconds: 10000)
    let finalizationTask = Task { await recorder.finalize() }
    await clock.waitForMonotonicReads(3)
    clock.advance(milliseconds: 5000)
    await recorder.setSettingsPresented(true)

    await repository.resumeFirstWrite()
    #expect(await finalizationTask.value == .saved)

    let final = try #require(await repository.records().last)
    let expectedEnd = Date(timeIntervalSince1970: 1015)
    #expect(final.endedAt == expectedEnd)
    #expect(final.lastPersistedAt == expectedEnd)
    #expect(final.practiceWindowDurationMilliseconds == 15000)
    #expect(final.activePracticeDurationMilliseconds == 15000)
}

@Test
func recorderSemanticEventsReturnBeforeSlowPersistenceCompletes() async throws {
    let repository = GatedRecorderRepository()
    let clock = try RecorderClock()
    let recorder = PracticeSessionRecorder(
        repository: repository,
        clock: clock.makeClock(),
        sleeper: RecorderSleeper()
    )
    await beginActiveVisit(recorder: recorder)
    let guidingCompletion = RecorderCompletionProbe()
    let settingsCompletion = RecorderCompletionProbe()

    let guidingTask = Task {
        _ = await recorder.setGuiding(true)
        await guidingCompletion.markCompleted()
    }
    await repository.waitUntilFirstWriteStarts()
    for _ in 0 ..< 20 {
        await Task.yield()
    }
    let guidingReturnedBeforeRelease = await guidingCompletion.isCompleted

    clock.advance(milliseconds: 10000)
    let settingsTask = Task {
        _ = await recorder.setSettingsPresented(true)
        await settingsCompletion.markCompleted()
    }
    for _ in 0 ..< 20 {
        await Task.yield()
    }
    let settingsReturnedBeforeRelease = await settingsCompletion.isCompleted

    await repository.resumeFirstWrite()
    await guidingTask.value
    await settingsTask.value
    #expect(guidingReturnedBeforeRelease)
    #expect(settingsReturnedBeforeRelease)
    #expect(await recorder.finalize() == .saved)
    let final = try #require(await repository.records().last)
    #expect(final.activePracticeDurationMilliseconds == 10000)
}

private actor GatedRecorderRepository: PracticeSessionRepositoryProtocol {
    private var firstWriteContinuation: CheckedContinuation<Void, Never>?
    private var didStartFirstWrite = false
    private var savedRecords: [PracticeSessionRecord] = []

    func upsert(_ session: PracticeSessionRecord) async {
        if didStartFirstWrite == false {
            didStartFirstWrite = true
            await withCheckedContinuation { firstWriteContinuation = $0 }
        }
        savedRecords.append(session)
    }

    func abandonLiveSession(id _: UUID) {}

    func waitUntilFirstWriteStarts() async {
        while didStartFirstWrite == false {
            await Task.yield()
        }
    }

    func resumeFirstWrite() {
        firstWriteContinuation?.resume()
        firstWriteContinuation = nil
    }

    func records() -> [PracticeSessionRecord] {
        savedRecords
    }
}

private actor RecorderCompletionProbe {
    private(set) var isCompleted = false

    func markCompleted() {
        isCompleted = true
    }
}
