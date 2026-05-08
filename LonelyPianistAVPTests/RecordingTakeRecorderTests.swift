@testable import LonelyPianistAVP
import Testing

@Test
func recorderStartStopProducesTake() {
    var recorder = RecordingTakeRecorder()
    recorder.start(now: 100.0)
    recorder.recordNoteOn(note: 60, velocity: 90, now: 100.5)
    recorder.recordNoteOff(note: 60, now: 100.7)
    let take = recorder.stop(now: 101.0)

    #expect(take.events.count == 2)
    #expect(take.events[0].kind == .noteOn(midi: 60, velocity: 90))
    #expect(take.events[1].kind == .noteOff(midi: 60))
    #expect(abs(take.events[0].time - 0.5) < 0.0001)
    #expect(abs(take.events[1].time - 0.7) < 0.0001)
}

@Test
func recorderHandlesRepeatedNoteOn() {
    var recorder = RecordingTakeRecorder()
    recorder.start(now: 0.0)
    recorder.recordNoteOn(note: 60, velocity: 90, now: 0.1)
    recorder.recordNoteOn(note: 60, velocity: 80, now: 0.3)
    let take = recorder.stop(now: 0.5)

    #expect(take.events.count == 4)
    #expect(take.events[0].kind == .noteOn(midi: 60, velocity: 90))
    #expect(take.events[1].kind == .noteOff(midi: 60))
    #expect(take.events[2].kind == .noteOn(midi: 60, velocity: 80))
    #expect(take.events[3].kind == .noteOff(midi: 60))
}

@Test
func recorderStopFlushesOpenNotes() {
    var recorder = RecordingTakeRecorder()
    recorder.start(now: 0.0)
    recorder.recordNoteOn(note: 64, velocity: 70, now: 0.2)
    let take = recorder.stop(now: 1.0)

    #expect(take.events.count == 2)
    #expect(take.events[0].kind == .noteOn(midi: 64, velocity: 70))
    #expect(take.events[1].kind == .noteOff(midi: 64))
    #expect(abs(take.events[1].time - 1.0) < 0.0001)
}

@Test
func recorderEventsAreSortedByTime() {
    var recorder = RecordingTakeRecorder()
    recorder.start(now: 0.0)
    recorder.recordNoteOn(note: 60, velocity: 90, now: 0.5)
    recorder.recordNoteOn(note: 64, velocity: 80, now: 0.1)
    recorder.recordNoteOff(note: 60, now: 0.8)
    recorder.recordNoteOff(note: 64, now: 0.4)
    let take = recorder.stop(now: 1.0)

    for i in 1..<take.events.count {
        #expect(take.events[i].time >= take.events[i - 1].time)
    }
}

@Test
func recorderIgnoresEventsWhenNotRecording() {
    var recorder = RecordingTakeRecorder()
    recorder.recordNoteOn(note: 60, velocity: 90, now: 0.0)
    recorder.recordNoteOff(note: 60, now: 0.1)
    let take = recorder.stop(now: 0.5)

    #expect(take.events.isEmpty)
}

@Test
func recorderClampsNoteAndVelocity() {
    var recorder = RecordingTakeRecorder()
    recorder.start(now: 0.0)
    recorder.recordNoteOn(note: 200, velocity: 200, now: 0.1)
    let take = recorder.stop(now: 0.5)

    #expect(take.events.count == 2)
    #expect(take.events[0].kind == .noteOn(midi: 127, velocity: 127))
}

@Test
func recorderClampsNoteOff() {
    var recorder = RecordingTakeRecorder()
    recorder.start(now: 0.0)
    recorder.recordNoteOn(note: 200, velocity: 90, now: 0.1)
    recorder.recordNoteOff(note: 200, now: 0.3)
    let take = recorder.stop(now: 0.5)

    #expect(take.events.count == 2)
    #expect(take.events[0].kind == .noteOn(midi: 127, velocity: 90))
    #expect(take.events[1].kind == .noteOff(midi: 127))
}

@Test
func recorderDurationBasedOnMaxEventTime() {
    var recorder = RecordingTakeRecorder()
    recorder.start(now: 0.0)
    recorder.recordNoteOn(note: 60, velocity: 90, now: 0.5)
    recorder.recordNoteOff(note: 60, now: 1.2)
    let take = recorder.stop(now: 2.0)

    #expect(abs(take.durationSeconds - 1.2) < 0.0001)
}
