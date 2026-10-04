import Foundation
import Practice
import MusicXML
import Diagnostics
@testable import HappyPianistAVP
import Testing

private enum DuetAIPlaybackQueueTestError: Error {
    case simulated
}

@MainActor
private final class FakeImmediatePlaybackService: TestPracticeSequencerPlaybackService {
    private(set) var stopCallCount = 0
    private(set) var warmUpCallCount = 0
    private(set) var loadCallCount = 0
    private(set) var playCallCount = 0

    private var loadedSequence: PracticeSequencerSequence?
    private var isPlaying = false
    private let failsWarmUp: Bool

    init(failsWarmUp: Bool = false) {
        self.failsWarmUp = failsWarmUp
    }

    func warmUp() throws {
        warmUpCallCount += 1
        if failsWarmUp {
            throw DuetAIPlaybackQueueTestError.simulated
        }
    }

    func stop(resetCommands _: [PerformanceTransportCommand]) {
        stopCallCount += 1
        isPlaying = false
    }

    func load(sequence: PracticeSequencerSequence) throws {
        loadCallCount += 1
        loadedSequence = sequence
    }

    func play(fromSeconds _: TimeInterval) throws {
        playCallCount += 1
        isPlaying = true
    }

    func currentSeconds() -> TimeInterval {
        guard isPlaying else { return 0 }
        return loadedSequence?.durationSeconds ?? 0
    }

    func playOneShot(commands _: [PracticePlaybackCommand], durationSeconds _: TimeInterval) throws {}
    func execute(commands _: [PracticePlaybackCommand]) throws {}
    func stopAllLiveNotes() {}
}

private actor SequenceBuildGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var didStart = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func build(_ schedule: [PracticeSequencerMIDIEvent]) async throws -> PracticeSequencerSequence {
        didStart = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        let end = schedule.map(\.timeSeconds).max() ?? 0
        return PracticeSequencerSequence(midiData: Data(), durationSeconds: end, events: schedule)
    }

    func waitForStart() async {
        guard didStart == false else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

private actor PlaybackWarmUpGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var didStart = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func warmUp() async {
        didStart = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitForStart() async {
        guard didStart == false else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

private actor GatedWarmUpPlaybackService: TestPracticeSequencerPlaybackService {
    private let warmUpGate: PlaybackWarmUpGate
    private(set) var warmUpCallCount = 0
    private(set) var loadCallCount = 0
    private(set) var playCallCount = 0

    init(warmUpGate: PlaybackWarmUpGate) {
        self.warmUpGate = warmUpGate
    }

    func warmUp() async throws {
        warmUpCallCount += 1
        await warmUpGate.warmUp()
    }

    func stop(resetCommands _: [PerformanceTransportCommand]) {}

    func load(sequence _: PracticeSequencerSequence) throws {
        loadCallCount += 1
    }

    func play(fromSeconds _: TimeInterval) throws {
        playCallCount += 1
    }

    func currentSeconds() -> TimeInterval {
        0
    }

    func playOneShot(commands _: [PracticePlaybackCommand], durationSeconds _: TimeInterval) throws {}
    func execute(commands _: [PracticePlaybackCommand]) throws {}
    func stopAllLiveNotes() {}

    func callCounts() -> (warmUp: Int, load: Int, play: Int) {
        (warmUpCallCount, loadCallCount, playCallCount)
    }
}

@Test
func duetAIPlaybackQueueSubmitWindowShiftsLeadInForQueuedWindows() async {
    let fakeService = await MainActor.run { FakeImmediatePlaybackService() }
    let factory = await MainActor.run {
        DuetAIPlaybackServiceFactory(
            makeLocalSamplerPlaybackService: { fakeService },
            makeExternalMIDIPlaybackService: { _ in fakeService }
        )
    }

    let queue = DuetAIPlaybackQueue(
        nowUptimeSeconds: { 100 },
        sleepFor: { _ in },
        buildSequence: { schedule in
            let end = schedule.map(\.timeSeconds).max() ?? 0
            return PracticeSequencerSequence(midiData: Data(), durationSeconds: end, events: schedule)
        },
        playbackServiceFactory: { factory },
        onPlaybackPhaseChanged: { _ in }
    )

    let routing = PracticeSoundRoutingSettings(outputRoute: .localSampler, midiDestinationUniqueID: nil, sendLocalControlOff: false)
    let schedule1 = [
        PracticeSequencerMIDIEvent(timeSeconds: 0.0, kind: .noteOn(midi: 60, velocity: 90)),
        PracticeSequencerMIDIEvent(timeSeconds: 0.1, kind: .noteOff(midi: 60)),
    ]
    let schedule2 = [
        PracticeSequencerMIDIEvent(timeSeconds: 0.0, kind: .noteOn(midi: 64, velocity: 90)),
        PracticeSequencerMIDIEvent(timeSeconds: 0.1, kind: .noteOff(midi: 64)),
    ]

    let result1 = await queue.submitWindow(schedule: schedule1, routing: routing, submittedAtUptimeSeconds: 100)
    #expect(abs(result1.baseDelaySeconds - 0.05) < 1e-9)
    #expect(result1.replacedPendingWindow == false)
    #expect(abs(result1.shiftedSchedule[0].timeSeconds - 0.05) < 1e-9)

    let result2 = await queue.submitWindow(schedule: schedule2, routing: routing, submittedAtUptimeSeconds: 100)
    #expect(abs(result2.baseDelaySeconds - 0.05) < 1e-9)
    #expect(abs(result2.shiftedSchedule[0].timeSeconds - 0.05) < 1e-9)
    #expect(abs(result2.windowEndUptimeSeconds - 100.15) < 1e-9)

    await queue.stopAll()
}

@Test
func duetAIPlaybackQueueBuildFailureDiagnosticIsClassified() async {
    let diagnosticsReporter = InMemoryDiagnosticsReporter()
    let fakeService = await MainActor.run { FakeImmediatePlaybackService() }
    let factory = await MainActor.run {
        DuetAIPlaybackServiceFactory(
            makeLocalSamplerPlaybackService: { fakeService },
            makeExternalMIDIPlaybackService: { _ in fakeService }
        )
    }
    let queue = DuetAIPlaybackQueue(
        diagnosticsReporter: diagnosticsReporter,
        nowUptimeSeconds: { 50 },
        sleepFor: { _ in },
        buildSequence: { _ in throw DuetAIPlaybackQueueTestError.simulated },
        playbackServiceFactory: { factory },
        onPlaybackPhaseChanged: { _ in }
    )
    let routing = PracticeSoundRoutingSettings(outputRoute: .localSampler, midiDestinationUniqueID: nil, sendLocalControlOff: false)
    _ = await queue.submitWindow(
        schedule: [PracticeSequencerMIDIEvent(timeSeconds: 0, kind: .noteOn(midi: 72, velocity: 80))],
        routing: routing,
        submittedAtUptimeSeconds: 50,
        provider: .localRule
    )

    await TestAsyncWait.until("sequence-build diagnostic") {
        let events = await diagnosticsReporter.events
        return events.contains(where: { $0.reason == "provider=local_rule;failure=sequence_build" })
    }

    let events = await diagnosticsReporter.events
    #expect(events.contains(where: { $0.reason == "provider=local_rule;failure=sequence_build" }))
    await queue.stopAll()
}

@Test
func duetAIPlaybackQueuePlaybackStartFailureDiagnosticIsClassified() async {
    let diagnosticsReporter = InMemoryDiagnosticsReporter()
    let fakeService = await MainActor.run { FakeImmediatePlaybackService(failsWarmUp: true) }
    let factory = await MainActor.run {
        DuetAIPlaybackServiceFactory(
            makeLocalSamplerPlaybackService: { fakeService },
            makeExternalMIDIPlaybackService: { _ in fakeService }
        )
    }
    let queue = DuetAIPlaybackQueue(
        diagnosticsReporter: diagnosticsReporter,
        nowUptimeSeconds: { 50 },
        sleepFor: { _ in },
        buildSequence: { schedule in
            let end = schedule.map(\.timeSeconds).max() ?? 0
            return PracticeSequencerSequence(midiData: Data(), durationSeconds: end, events: schedule)
        },
        playbackServiceFactory: { factory },
        onPlaybackPhaseChanged: { _ in }
    )
    let routing = PracticeSoundRoutingSettings(outputRoute: .localSampler, midiDestinationUniqueID: nil, sendLocalControlOff: false)
    _ = await queue.submitWindow(
        schedule: [PracticeSequencerMIDIEvent(timeSeconds: 0, kind: .noteOn(midi: 72, velocity: 80))],
        routing: routing,
        submittedAtUptimeSeconds: 50,
        provider: .localCoreMLDuet
    )

    await TestAsyncWait.until("playback-start diagnostic") {
        let events = await diagnosticsReporter.events
        return events.contains(where: { $0.reason == "provider=local_coreml_duet;failure=playback_start" })
    }

    let events = await diagnosticsReporter.events
    #expect(events.contains(where: { $0.reason == "provider=local_coreml_duet;failure=playback_start" }))
    await queue.stopAll()
}

@Test
func duetAIPlaybackQueueClearUnstartedWindowsDropsQueuedReplacement() async {
    let fakeService = await MainActor.run { FakeImmediatePlaybackService() }
    let factory = await MainActor.run {
        DuetAIPlaybackServiceFactory(
            makeLocalSamplerPlaybackService: { fakeService },
            makeExternalMIDIPlaybackService: { _ in fakeService }
        )
    }

    let gate = SequenceBuildGate()
    let queue = DuetAIPlaybackQueue(
        nowUptimeSeconds: { 50 },
        sleepFor: { _ in },
        buildSequence: { schedule in try await gate.build(schedule) },
        playbackServiceFactory: { factory },
        onPlaybackPhaseChanged: { _ in }
    )

    let routing = PracticeSoundRoutingSettings(outputRoute: .localSampler, midiDestinationUniqueID: nil, sendLocalControlOff: false)
    let currentSchedule = [
        PracticeSequencerMIDIEvent(timeSeconds: 0.0, kind: .noteOn(midi: 72, velocity: 80)),
        PracticeSequencerMIDIEvent(timeSeconds: 0.1, kind: .noteOff(midi: 72)),
    ]
    let replacementSchedule = [
        PracticeSequencerMIDIEvent(timeSeconds: 0.0, kind: .noteOn(midi: 76, velocity: 80)),
        PracticeSequencerMIDIEvent(timeSeconds: 0.1, kind: .noteOff(midi: 76)),
    ]

    _ = await queue.submitWindow(schedule: currentSchedule, routing: routing, submittedAtUptimeSeconds: 50)
    await gate.waitForStart()
    let replacement = await queue.submitWindow(schedule: replacementSchedule, routing: routing, submittedAtUptimeSeconds: 50)
    #expect(abs(replacement.baseDelaySeconds - 0.05) < 1e-9)
    await queue.clearUnstartedWindows()
    await gate.resume()
    for _ in 0 ..< 200 {
        await Task.yield()
    }

    let counts = await MainActor.run { (fakeService.loadCallCount, fakeService.playCallCount) }
    #expect(counts.0 == 0)
    #expect(counts.1 == 0)
    await queue.stopAll()
}

@Test
func duetAIPlaybackQueueStopAllPreventsLateBuildFromStartingPlayback() async {
    let fakeService = await MainActor.run { FakeImmediatePlaybackService() }
    let factory = await MainActor.run {
        DuetAIPlaybackServiceFactory(
            makeLocalSamplerPlaybackService: { fakeService },
            makeExternalMIDIPlaybackService: { _ in fakeService }
        )
    }
    let gate = SequenceBuildGate()
    let queue = DuetAIPlaybackQueue(
        nowUptimeSeconds: { 50 },
        sleepFor: { _ in },
        buildSequence: { schedule in try await gate.build(schedule) },
        playbackServiceFactory: { factory },
        onPlaybackPhaseChanged: { _ in }
    )
    let routing = PracticeSoundRoutingSettings(outputRoute: .localSampler, midiDestinationUniqueID: nil, sendLocalControlOff: false)
    _ = await queue.submitWindow(
        schedule: [PracticeSequencerMIDIEvent(timeSeconds: 0, kind: .noteOn(midi: 72, velocity: 80))],
        routing: routing,
        submittedAtUptimeSeconds: 50
    )
    await gate.waitForStart()

    await queue.stopAll()
    await gate.resume()
    for _ in 0 ..< 200 {
        await Task.yield()
    }

    let counts = await MainActor.run { (fakeService.warmUpCallCount, fakeService.loadCallCount, fakeService.playCallCount) }
    #expect(counts.0 == 0)
    #expect(counts.1 == 0)
    #expect(counts.2 == 0)
}

@Test
func duetAIPlaybackQueueStopAllPreventsPostWarmUpCommands() async {
    let warmUpGate = PlaybackWarmUpGate()
    let fakeService = GatedWarmUpPlaybackService(warmUpGate: warmUpGate)
    let factory = await MainActor.run {
        DuetAIPlaybackServiceFactory(
            makeLocalSamplerPlaybackService: { fakeService },
            makeExternalMIDIPlaybackService: { _ in fakeService }
        )
    }
    let queue = DuetAIPlaybackQueue(
        nowUptimeSeconds: { 50 },
        sleepFor: { _ in },
        buildSequence: { schedule in
            let end = schedule.map(\.timeSeconds).max() ?? 0
            return PracticeSequencerSequence(midiData: Data(), durationSeconds: end, events: schedule)
        },
        playbackServiceFactory: { factory },
        onPlaybackPhaseChanged: { _ in }
    )
    let routing = PracticeSoundRoutingSettings(outputRoute: .localSampler, midiDestinationUniqueID: nil, sendLocalControlOff: false)
    _ = await queue.submitWindow(
        schedule: [PracticeSequencerMIDIEvent(timeSeconds: 0, kind: .noteOn(midi: 72, velocity: 80))],
        routing: routing,
        submittedAtUptimeSeconds: 50
    )
    await warmUpGate.waitForStart()

    await queue.stopAll()
    await warmUpGate.resume()
    for _ in 0 ..< 200 {
        await Task.yield()
    }

    let counts = await fakeService.callCounts()
    #expect(counts.warmUp == 1)
    #expect(counts.load == 0)
    #expect(counts.play == 0)
}

@Test
func duetAIPlaybackQueueIgnoresSupersededTeardown() async {
    let warmUpGate = PlaybackWarmUpGate()
    let fakeService = GatedWarmUpPlaybackService(warmUpGate: warmUpGate)
    let factory = await MainActor.run {
        DuetAIPlaybackServiceFactory(
            makeLocalSamplerPlaybackService: { fakeService },
            makeExternalMIDIPlaybackService: { _ in fakeService }
        )
    }
    let queue = DuetAIPlaybackQueue(
        nowUptimeSeconds: { 50 },
        sleepFor: { _ in },
        buildSequence: { schedule in
            let end = schedule.map(\.timeSeconds).max() ?? 0
            return PracticeSequencerSequence(midiData: Data(), durationSeconds: end, events: schedule)
        },
        playbackServiceFactory: { factory },
        onPlaybackPhaseChanged: { _ in }
    )
    let routing = PracticeSoundRoutingSettings(outputRoute: .localSampler, midiDestinationUniqueID: nil, sendLocalControlOff: false)
    await queue.invalidateUnstartedWindows(through: 2)
    _ = await queue.submitWindow(
        schedule: [PracticeSequencerMIDIEvent(timeSeconds: 0, kind: .noteOn(midi: 72, velocity: 80))],
        routing: routing,
        submittedAtUptimeSeconds: 50,
        requestGeneration: 2
    )
    await warmUpGate.waitForStart()

    await queue.stopAll(rejectingThrough: 1)
    await warmUpGate.resume()
    for _ in 0 ..< 200 {
        await Task.yield()
    }

    let counts = await fakeService.callCounts()
    #expect(counts.load == 1)
    #expect(counts.play == 1)
    await queue.stopAll()
}

@MainActor
private final class PlaybackPhaseRecorder {
    private(set) var phases: [DuetAIPlaybackQueue.PlaybackPhase] = []

    func record(_ phase: DuetAIPlaybackQueue.PlaybackPhase) {
        phases.append(phase)
    }
}

@MainActor
private final class HoldingPlaybackService: TestPracticeSequencerPlaybackService {
    private(set) var stopCallCount = 0
    private(set) var playCallCount = 0
    private(set) var isPlaying = false

    func warmUp() throws {}

    func stop(resetCommands _: [PerformanceTransportCommand]) {
        stopCallCount += 1
        isPlaying = false
    }

    func load(sequence _: PracticeSequencerSequence) throws {}

    func play(fromSeconds _: TimeInterval) throws {
        playCallCount += 1
        isPlaying = true
    }

    func currentSeconds() -> TimeInterval { 0 }
    func playOneShot(commands _: [PracticePlaybackCommand], durationSeconds _: TimeInterval) throws {}
    func execute(commands _: [PracticePlaybackCommand]) throws {}
    func stopAllLiveNotes() {}
}

private actor PlaybackStartGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var didStart = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func block() async {
        didStart = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitForStart() async {
        guard didStart == false else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

private actor GatedPlayPlaybackService: TestPracticeSequencerPlaybackService {
    private let gate: PlaybackStartGate
    private var stopCallCountValue = 0
    private var loadCallCountValue = 0
    private var playCallCountValue = 0

    init(gate: PlaybackStartGate) {
        self.gate = gate
    }

    func warmUp() throws {}

    func stop(resetCommands _: [PerformanceTransportCommand]) {
        stopCallCountValue += 1
    }

    func load(sequence _: PracticeSequencerSequence) throws {
        loadCallCountValue += 1
    }

    func play(fromSeconds _: TimeInterval) async throws {
        playCallCountValue += 1
        await gate.block()
    }

    func currentSeconds() -> TimeInterval { 0 }
    func playOneShot(commands _: [PracticePlaybackCommand], durationSeconds _: TimeInterval) throws {}
    func execute(commands _: [PracticePlaybackCommand]) throws {}
    func stopAllLiveNotes() {}

    func counts() -> (stop: Int, load: Int, play: Int) {
        (stopCallCountValue, loadCallCountValue, playCallCountValue)
    }
}

@Test
func duetAIPlaybackQueueReportsPreparingPlayingIdleAtRealPlaybackBoundaries() async {
    let fakeService = await MainActor.run { FakeImmediatePlaybackService() }
    let recorder = await MainActor.run { PlaybackPhaseRecorder() }
    let factory = await MainActor.run {
        DuetAIPlaybackServiceFactory(
            makeLocalSamplerPlaybackService: { fakeService },
            makeExternalMIDIPlaybackService: { _ in fakeService }
        )
    }
    let queue = DuetAIPlaybackQueue(
        nowUptimeSeconds: { 10 },
        sleepFor: { _ in },
        buildSequence: { schedule in
            let end = schedule.map(\.timeSeconds).max() ?? 0
            return PracticeSequencerSequence(midiData: Data(), durationSeconds: end, events: schedule)
        },
        playbackServiceFactory: { factory },
        onPlaybackPhaseChanged: { recorder.record($0) }
    )
    let routing = PracticeSoundRoutingSettings(
        outputRoute: .localSampler,
        midiDestinationUniqueID: nil,
        sendLocalControlOff: false
    )

    _ = await queue.submitWindow(
        schedule: [
            PracticeSequencerMIDIEvent(timeSeconds: 0, kind: .noteOn(midi: 60, velocity: 90)),
            PracticeSequencerMIDIEvent(timeSeconds: 0.1, kind: .noteOff(midi: 60)),
        ],
        routing: routing,
        submittedAtUptimeSeconds: 10,
        requestGeneration: 1
    )

    for _ in 0 ..< 200 {
        let phases = await MainActor.run { recorder.phases }
        if phases == [.preparing, .playing, .idle] { break }
        await Task.yield()
    }

    #expect(await MainActor.run { recorder.phases } == [.preparing, .playing, .idle])
    await queue.stopAll()
}

@Test
func duetAIPlaybackQueueInvalidatingNewInputDoesNotStopAlreadyPlayingWindow() async {
    let fakeService = await MainActor.run { HoldingPlaybackService() }
    let recorder = await MainActor.run { PlaybackPhaseRecorder() }
    let factory = await MainActor.run {
        DuetAIPlaybackServiceFactory(
            makeLocalSamplerPlaybackService: { fakeService },
            makeExternalMIDIPlaybackService: { _ in fakeService }
        )
    }
    let queue = DuetAIPlaybackQueue(
        nowUptimeSeconds: { 20 },
        sleepFor: { _ in await Task.yield() },
        buildSequence: { schedule in
            PracticeSequencerSequence(midiData: Data(), durationSeconds: 10, events: schedule)
        },
        playbackServiceFactory: { factory },
        onPlaybackPhaseChanged: { recorder.record($0) }
    )
    let routing = PracticeSoundRoutingSettings(
        outputRoute: .localSampler,
        midiDestinationUniqueID: nil,
        sendLocalControlOff: false
    )

    _ = await queue.submitWindow(
        schedule: [PracticeSequencerMIDIEvent(timeSeconds: 0, kind: .noteOn(midi: 60, velocity: 90))],
        routing: routing,
        submittedAtUptimeSeconds: 20,
        requestGeneration: 1
    )
    for _ in 0 ..< 200 {
        let didReachPlaying = await MainActor.run { recorder.phases.last == .playing }
        if didReachPlaying { break }
        await Task.yield()
    }

    let stopCountBeforeInput = await MainActor.run { fakeService.stopCallCount }
    await queue.invalidateUnstartedWindows(through: 2)
    for _ in 0 ..< 50 { await Task.yield() }

    #expect(await MainActor.run { recorder.phases.last } == .playing)
    #expect(await MainActor.run { fakeService.isPlaying })
    #expect(await MainActor.run { fakeService.stopCallCount } == stopCountBeforeInput)

    await queue.stopCurrentPlaybackAndClearPending()
    #expect(await MainActor.run { recorder.phases.last } == .idle)
    #expect(await MainActor.run { fakeService.isPlaying } == false)
    #expect(await MainActor.run { fakeService.stopCallCount } > stopCountBeforeInput)
}

@Test
func duetAIPlaybackQueueRechecksStaleGenerationAfterServicePlayReturns() async {
    let gate = PlaybackStartGate()
    let fakeService = GatedPlayPlaybackService(gate: gate)
    let recorder = await MainActor.run { PlaybackPhaseRecorder() }
    let factory = await MainActor.run {
        DuetAIPlaybackServiceFactory(
            makeLocalSamplerPlaybackService: { fakeService },
            makeExternalMIDIPlaybackService: { _ in fakeService }
        )
    }
    let queue = DuetAIPlaybackQueue(
        nowUptimeSeconds: { 30 },
        sleepFor: { _ in },
        buildSequence: { schedule in
            PracticeSequencerSequence(midiData: Data(), durationSeconds: 5, events: schedule)
        },
        playbackServiceFactory: { factory },
        onPlaybackPhaseChanged: { recorder.record($0) }
    )
    let routing = PracticeSoundRoutingSettings(
        outputRoute: .localSampler,
        midiDestinationUniqueID: nil,
        sendLocalControlOff: false
    )

    _ = await queue.submitWindow(
        schedule: [PracticeSequencerMIDIEvent(timeSeconds: 0, kind: .noteOn(midi: 64, velocity: 90))],
        routing: routing,
        submittedAtUptimeSeconds: 30,
        requestGeneration: 1
    )
    await gate.waitForStart()
    await queue.invalidateUnstartedWindows(through: 2)
    await gate.resume()

    for _ in 0 ..< 200 {
        let didReachIdle = await MainActor.run { recorder.phases.last == .idle }
        if didReachIdle { break }
        await Task.yield()
    }

    let counts = await fakeService.counts()
    #expect(counts.play == 1)
    #expect(counts.load == 1)
    #expect(counts.stop >= 2)
    #expect(await MainActor.run { recorder.phases.contains(.playing) } == false)
    #expect(await MainActor.run { recorder.phases.last } == .idle)
    await queue.stopAll()
}

@Test
func duetAIPlaybackQueueSameGenerationInvalidationDoesNotCancelCurrentPreparation() async {
    let fakeService = await MainActor.run { FakeImmediatePlaybackService() }
    let factory = await MainActor.run {
        DuetAIPlaybackServiceFactory(
            makeLocalSamplerPlaybackService: { fakeService },
            makeExternalMIDIPlaybackService: { _ in fakeService }
        )
    }
    let gate = SequenceBuildGate()
    let queue = DuetAIPlaybackQueue(
        nowUptimeSeconds: { 40 },
        sleepFor: { _ in },
        buildSequence: { schedule in try await gate.build(schedule) },
        playbackServiceFactory: { factory },
        onPlaybackPhaseChanged: { _ in }
    )
    let routing = PracticeSoundRoutingSettings(
        outputRoute: .localSampler,
        midiDestinationUniqueID: nil,
        sendLocalControlOff: false
    )

    _ = await queue.submitWindow(
        schedule: [
            PracticeSequencerMIDIEvent(timeSeconds: 0, kind: .noteOn(midi: 60, velocity: 90)),
            PracticeSequencerMIDIEvent(timeSeconds: 0.1, kind: .noteOff(midi: 60)),
        ],
        routing: routing,
        submittedAtUptimeSeconds: 40,
        requestGeneration: 1
    )
    await gate.waitForStart()
    await queue.invalidateUnstartedWindows(through: 1)
    await gate.resume()

    await TestAsyncWait.until("same-generation prepared window starts") {
        await MainActor.run { fakeService.playCallCount == 1 }
    }
    #expect(await MainActor.run { fakeService.playCallCount } == 1)
    await queue.stopAll()
}
