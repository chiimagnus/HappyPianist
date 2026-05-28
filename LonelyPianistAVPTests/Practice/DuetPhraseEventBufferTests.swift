import Foundation
import ImprovProtocol
@testable import LonelyPianistAVP
import Testing

@Test
func duetPhraseEventBufferFlushRebasesUnder10Seconds() {
    var buffer = DuetPhraseEventBuffer()
    buffer.recordPhraseStartIfNeeded(timestampSeconds: 1.0)
    buffer.recordControlChange(controller: 64, value: 127, timestampSeconds: 1.1)
    buffer.recordControlChange(controller: 1, value: 64, timestampSeconds: 1.2) // ignored

    let flushedNotes = DuetPhraseBuffer.FlushResult(trimmedNotes: [], untrimmedEndTimeSeconds: 0.5, endTimeSeconds: 0.5)
    let events = buffer.flushPhrase(flushedPhrase: flushedNotes)
    #expect(events.count == 1)
    #expect(events[0].type == .cc)
    #expect(events[0].controller == 64)
    #expect(events[0].value == 127)
    #expect(abs(events[0].time - 0.1) < 1e-9)
}

@Test
func duetPhraseEventBufferFlushTrimsLast15SecondsWhenOver10Seconds() {
    var buffer = DuetPhraseEventBuffer()
    buffer.recordPhraseStartIfNeeded(timestampSeconds: 100.0)
    buffer.recordControlChange(controller: 64, value: 127, timestampSeconds: 101.0) // should be trimmed out
    buffer.recordControlChange(controller: 7, value: 80, timestampSeconds: 120.0) // should remain

    let flushedNotes = DuetPhraseBuffer.FlushResult(trimmedNotes: [], untrimmedEndTimeSeconds: 20.2, endTimeSeconds: 15.0)
    let events = buffer.flushPhrase(flushedPhrase: flushedNotes)
    #expect(events.count == 1)
    #expect(events[0].type == .cc)
    #expect(events[0].controller == 7)
    #expect(events[0].value == 80)
    // windowStart = 20.2 - 15 = 5.2; (120 - 100) - 5.2 = 14.8
    #expect(abs(events[0].time - 14.8) < 1e-9)
}

