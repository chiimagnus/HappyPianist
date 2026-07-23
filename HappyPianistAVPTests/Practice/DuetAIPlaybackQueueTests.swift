import Foundation
@testable import HappyPianistAVP
import Testing

private enum DuetAIPlaybackQueueTestError: Error {
    case simulated
}

@MainActor
private final class FakeImmediatePlaybackService: PracticeSequencerPlaybackServiceProtocol {
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

private actor GatedWarmUpPlaybackService: PracticeSequencerPlaybackServiceProtocol {
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
        onPlaybackActiveChanged: { _ in }
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
        onPlaybackActiveChanged: { _ in }
    )
    let routing = PracticeSoundRoutingSettings(outputRoute: .localSampler, midiDestinationUniqueID: nil, sendLocalControlOff: false)
    _ = await queue.submitWindow(
        schedule: [PracticeSequencerMIDIEvent(timeSeconds: 0, kind: .noteOn(midi: 72, velocity: 80))],
        routing: routing,
        submittedAtUptimeSeconds: 50,
        provider: .localRule
    )

    for _ in 0 ..< 200 {
        await Task.yield()
        let events = await diagnosticsReporter.events
        if events.contains(where: { $0.reason == "provider=local_rule;failure=sequence_build" }) { break }
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
        onPlaybackActiveChanged: { _ in }
    )
    let routing = PracticeSoundRoutingSettings(outputRoute: .localSampler, midiDestinationUniqueID: nil, sendLocalControlOff: false)
    _ = await queue.submitWindow(
        schedule: [PracticeSequencerMIDIEvent(timeSeconds: 0, kind: .noteOn(midi: 72, velocity: 80))],
        routing: routing,
        submittedAtUptimeSeconds: 50,
        provider: .localCoreMLDuet
    )

    for _ in 0 ..< 200 {
        await Task.yield()
        let events = await diagnosticsReporter.events
        if events.contains(where: { $0.reason == "provider=local_coreml_duet;failure=playback_start" }) { break }
    }

    let events = await diagnosticsReporter.events
    #expect(events.contains(where: { $0.reason == "provider=local_coreml_duet;failure=playback_start" }))
    await queue.stopAll()
}

@Test
func duetAIPlaybackQueueClearPendingWindowDropsQueuedReplacement() async {
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
        onPlaybackActiveChanged: { _ in }
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
    await queue.clearPendingWindow()
    await gate.resume()
    for _ in 0 ..< 200 {
        await Task.yield()
    }

    let counts = await MainActor.run { (fakeService.loadCallCount, fakeService.playCallCount) }
    #expect(counts.0 == 1)
    #expect(counts.1 == 1)
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
        onPlaybackActiveChanged: { _ in }
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
        onPlaybackActiveChanged: { _ in }
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
        onPlaybackActiveChanged: { _ in }
    )
    let routing = PracticeSoundRoutingSettings(outputRoute: .localSampler, midiDestinationUniqueID: nil, sendLocalControlOff: false)
    await queue.invalidatePendingWindows(through: 2)
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
