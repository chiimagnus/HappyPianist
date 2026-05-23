import Foundation
import ImprovProtocol
@testable import LonelyPianistAVP
import Testing

@Test
func phraseRecorderFlushRebasesTimeAndClosesOpenNotes() {
    var recorder = PhraseRecorder()

    recorder.recordNoteOn(midi: 60, velocity: 90, timestamp: 100.0)
    recorder.recordNoteOff(midi: 60, timestamp: 100.2)

    recorder.recordNoteOn(midi: 64, velocity: 80, timestamp: 100.4)
    let phrase = recorder.flushPhrase(endTimestamp: 100.6)

    #expect(phrase.count == 2)

    let c4 = phrase.first { $0.note == 60 }
    let e4 = phrase.first { $0.note == 64 }
    #expect(c4 != nil)
    #expect(e4 != nil)

    #expect(abs((c4?.time ?? 1) - 0) < 0.001)
    #expect((c4?.duration ?? 0) >= 0.199)
    #expect((e4?.time ?? 0) >= 0.0)
    #expect((e4?.duration ?? 0) >= 0.199)
}

@Test
func silenceTriggerFiresAfterTimeoutOncePerPhrase() {
    var trigger = NoteOnSilenceTrigger()

    trigger.recordNoteOn(atUptime: 10.0)
    #expect(trigger.pollShouldTrigger(atUptime: 11.9, timeoutSeconds: 2.0) == false)
    #expect(trigger.pollShouldTrigger(atUptime: 12.0, timeoutSeconds: 2.0) == true)
    #expect(trigger.pollShouldTrigger(atUptime: 12.5, timeoutSeconds: 2.0) == false)

    trigger.recordNoteOn(atUptime: 20.0)
    #expect(trigger.pollShouldTrigger(atUptime: 22.0, timeoutSeconds: 2.0) == true)
}
