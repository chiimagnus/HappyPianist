import Foundation
@testable import HappyPianistAVP
import Testing

@Test
func adapterProducesNonEmptyScheduleFromTake() {
    let take = RecordingTake(
        name: "Test",
        events: [
            RecordingTakeEvent(time: 0.0, kind: .noteOn(midi: 60, velocity: 90)),
            RecordingTakeEvent(time: 0.5, kind: .noteOff(midi: 60)),
        ]
    )
    let adapter = RecordingTakeSequenceAdapter()
    let schedule = adapter.makeMIDISchedule(from: take)

    #expect(schedule.count == 2)
    #expect(schedule[0].kind == .noteOn(midi: 60, velocity: 90))
    #expect(schedule[1].kind == .noteOff(midi: 60))
}

@Test
func adapterBuildsNonEmptySequence() throws {
    let take = RecordingTake(
        name: "Test",
        events: [
            RecordingTakeEvent(time: 0.0, kind: .noteOn(midi: 60, velocity: 90)),
            RecordingTakeEvent(time: 0.5, kind: .noteOff(midi: 60)),
        ]
    )
    let adapter = RecordingTakeSequenceAdapter()
    let sequence = try adapter.buildSequence(from: take)

    #expect(sequence.midiData.isEmpty == false)
    #expect(sequence.durationSeconds > 0)
}

@Test
func adapterClampsVelocityToMIDIRange() {
    let take = RecordingTake(
        name: "Test",
        events: [
            RecordingTakeEvent(time: 0.0, kind: .noteOn(midi: 60, velocity: 200)),
            RecordingTakeEvent(time: 0.5, kind: .noteOff(midi: 60)),
        ]
    )
    let adapter = RecordingTakeSequenceAdapter()
    let schedule = adapter.makeMIDISchedule(from: take)

    if case let .noteOn(_, velocity) = schedule[0].kind {
        #expect(velocity == 127)
    } else {
        Issue.record("Expected noteOn")
    }
}

@Test
func adapterHandlesEmptyTake() {
    let take = RecordingTake(name: "Empty", events: [])
    let adapter = RecordingTakeSequenceAdapter()
    let schedule = adapter.makeMIDISchedule(from: take)

    #expect(schedule.isEmpty)
}

@Test
@MainActor
func takePlaybackStopInvalidatesSuspendedPlayBeforeLoad() async throws {
    let playback = SuspendingTakePlaybackService()
    let controller = TakePlaybackController(playbackService: playback)
    let take = RecordingTake(
        name: "Race",
        events: [
            RecordingTakeEvent(time: 0, kind: .noteOn(midi: 60, velocity: 90)),
            RecordingTakeEvent(time: 0.1, kind: .noteOff(midi: 60)),
        ]
    )

    let playTask = Task { try await controller.play(take: take) }
    await playback.waitForFirstStop()
    let stopTask = Task { await controller.stop() }
    await playback.waitForStopCount(2)
    await playback.resumeFirstStop()
    try await playTask.value
    await stopTask.value

    let calls = await playback.calls()
    #expect(calls.load == 0)
    #expect(calls.play == 0)
    #expect(controller.isPlaying == false)
}

private actor SuspendingTakePlaybackService: PracticeSequencerPlaybackServiceProtocol {
    private var stopCount = 0
    private var loadCount = 0
    private var playCount = 0
    private var firstStopContinuation: CheckedContinuation<Void, Never>?

    func warmUp() async throws {}

    func stop(resetCommands _: [PerformanceTransportCommand]) async {
        stopCount += 1
        guard stopCount == 1 else { return }
        await withCheckedContinuation { continuation in
            firstStopContinuation = continuation
        }
    }

    func load(sequence _: PracticeSequencerSequence) async throws {
        loadCount += 1
    }

    func play(fromSeconds _: TimeInterval) async throws {
        playCount += 1
    }

    func currentSeconds() async -> TimeInterval {
        0
    }

    func playOneShot(commands _: [PracticePlaybackCommand], durationSeconds _: TimeInterval) async throws {}
    func execute(commands _: [PracticePlaybackCommand]) async throws {}
    func stopAllLiveNotes() async {}

    func waitForFirstStop() async {
        while stopCount == 0 {
            await Task.yield()
        }
    }

    func waitForStopCount(_ expectedCount: Int) async {
        while stopCount < expectedCount {
            await Task.yield()
        }
    }

    func resumeFirstStop() {
        firstStopContinuation?.resume()
        firstStopContinuation = nil
    }

    func calls() -> (load: Int, play: Int) {
        (loadCount, playCount)
    }
}
