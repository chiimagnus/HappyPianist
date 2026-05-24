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
func duetAIPlaybackQueueShiftsFirstNoteOnToLeadInAndKeepsAIEndMonotonic() async {
    let fakeService = await MainActor.run { FakeImmediatePlaybackService() }
    let factory = await MainActor.run {
        DuetAIPlaybackServiceFactory(
            makeLocalSamplerPlaybackService: { fakeService },
            makeExternalMIDIPlaybackService: { _ in fakeService }
        )
    }

    let queue = DuetAIPlaybackQueue(
        logger: Logger(subsystem: "test", category: "ai-playback-queue"),
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

    let result1 = await queue.enqueue(schedule: schedule1, routing: routing, enqueuedAtUptimeSeconds: 100)
    #expect(abs(result1.baseDelaySeconds - 0.05) < 1e-9)
    if case let .noteOn(midi, _) = result1.shiftedSchedule[0].kind {
        #expect(midi == 60)
    } else {
        #expect(Bool(false))
    }
    #expect(abs(result1.shiftedSchedule[0].timeSeconds - 0.05) < 1e-9)

    let schedule2 = [
        PracticeSequencerMIDIEvent(timeSeconds: 0.0, kind: .noteOn(midi: 64, velocity: 90)),
        PracticeSequencerMIDIEvent(timeSeconds: 0.1, kind: .noteOff(midi: 64)),
    ]
    let result2 = await queue.enqueue(schedule: schedule2, routing: routing, enqueuedAtUptimeSeconds: 100)
    #expect(abs(result2.baseDelaySeconds - 0.05) < 1e-9)
    #expect(abs(result2.shiftedSchedule[0].timeSeconds - 0.05) < 1e-9)

    await queue.stopAll()
}

