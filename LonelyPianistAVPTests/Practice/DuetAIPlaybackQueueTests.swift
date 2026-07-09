import Foundation
@testable import LonelyPianistAVP
import os
import Testing

@MainActor
private final class FakeImmediatePlaybackService: PracticeSequencerPlaybackServiceProtocol {
    private(set) var stopCallCount = 0
    private(set) var loadCallCount = 0
    private(set) var playCallCount = 0

    private var loadedSequence: PracticeSequencerSequence?
    private var isPlaying = false

    func warmUp() throws {}

    func stop() {
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

    func playOneShot(noteOns _: [PracticeOneShotNoteOn], durationSeconds _: TimeInterval) throws {}
    func startLiveNotes(midiNotes _: Set<Int>) throws {}
    func stopLiveNotes(midiNotes _: Set<Int>) {}
    func stopAllLiveNotes() {}
}

@Test
func duetAIPlaybackQueueSubmitWindowShiftsLeadInAndReplacesPendingWindow() async {
    let fakeService = await MainActor.run { FakeImmediatePlaybackService() }
    let factory = await MainActor.run {
        DuetAIPlaybackServiceFactory(
            makeLocalSamplerPlaybackService: { fakeService },
            makeExternalMIDIPlaybackService: { _ in fakeService }
        )
    }

    let queue = DuetAIPlaybackQueue(
        logger: Logger(subsystem: "test", category: "continuous-duet-queue"),
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
    #expect(abs(result2.baseDelaySeconds - 0.15) < 1e-9)
    #expect(result2.replacedPendingWindow)
    #expect(abs(result2.shiftedSchedule[0].timeSeconds - 0.15) < 1e-9)
    #expect(abs(result2.windowEndUptimeSeconds - 100.25) < 1e-9)

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

    let queue = DuetAIPlaybackQueue(
        logger: Logger(subsystem: "test", category: "continuous-duet-queue"),
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
    let schedule = [
        PracticeSequencerMIDIEvent(timeSeconds: 0.0, kind: .noteOn(midi: 72, velocity: 80)),
        PracticeSequencerMIDIEvent(timeSeconds: 0.1, kind: .noteOff(midi: 72)),
    ]

    _ = await queue.submitWindow(schedule: schedule, routing: routing, submittedAtUptimeSeconds: 50)
    await queue.clearPendingWindow()
    await queue.stopAll()
    let stopCount = await MainActor.run { fakeService.stopCallCount }
    #expect(stopCount >= 1)
}
