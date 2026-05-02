@testable import LonelyPianistAVP
import Testing

@Test
func recorderRecordsNoteOnOffWithRebasedTime() {
    var recorder = PhraseRecorder()
    recorder.recordNoteOn(midi: 60, velocity: 90, timestamp: 10.0)
    recorder.recordNoteOff(midi: 60, timestamp: 10.2)

    let phrase = recorder.flushPhrase(endTimestamp: 10.2)
    #expect(phrase.count == 1)
    #expect(phrase[0].note == 60)
    #expect(phrase[0].velocity == 90)
    #expect(abs(phrase[0].time - 0.0) < 0.0001)
    #expect(abs(phrase[0].duration - 0.2) < 0.0001)
}

@Test
func recorderClampsMinimumDuration() {
    var recorder = PhraseRecorder()
    recorder.recordNoteOn(midi: 60, velocity: 90, timestamp: 1.0)
    recorder.recordNoteOff(midi: 60, timestamp: 1.001)

    let phrase = recorder.flushPhrase(endTimestamp: 1.001)
    #expect(phrase.count == 1)
    #expect(phrase[0].duration >= 0.05)
}

@Test
func recorderFlushesOpenNotes() {
    var recorder = PhraseRecorder()
    recorder.recordNoteOn(midi: 64, velocity: 70, timestamp: 5.0)

    let phrase = recorder.flushPhrase(endTimestamp: 5.4)
    #expect(phrase.count == 1)
    #expect(phrase[0].note == 64)
    #expect(abs(phrase[0].time - 0.0) < 0.0001)
    #expect(abs(phrase[0].duration - 0.4) < 0.0001)
}

@Test
func recorderHandlesRepeatedNoteOnWithoutCrashing() {
    var recorder = PhraseRecorder()
    recorder.recordNoteOn(midi: 60, velocity: 90, timestamp: 0.0)
    recorder.recordNoteOn(midi: 60, velocity: 80, timestamp: 0.1)

    let phrase = recorder.flushPhrase(endTimestamp: 0.2)
    #expect(phrase.count == 2)
    #expect(abs(phrase[0].time - 0.0) < 0.0001)
    #expect(abs(phrase[1].time - 0.1) < 0.0001)
    #expect(phrase[0].velocity == 90)
    #expect(phrase[1].velocity == 80)
}

@Test
func recorderIgnoresNoteOffWithoutNoteOn() {
    var recorder = PhraseRecorder()
    recorder.recordNoteOff(midi: 60, timestamp: 0.2)

    let phrase = recorder.flushPhrase(endTimestamp: 0.2)
    #expect(phrase.isEmpty)
}

