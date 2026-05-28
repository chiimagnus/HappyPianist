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

@Test
func duetPhraseEventBufferInjectsInitialCCStateWhenCCArrivesBeforePhraseStart() {
    var buffer = DuetPhraseEventBuffer()

    buffer.recordControlChange(controller: 64, value: 127, timestampSeconds: 0.5)
    buffer.recordControlChange(controller: 7, value: 80, timestampSeconds: 0.6)
    buffer.recordControlChange(controller: 11, value: 90, timestampSeconds: 0.7)

    buffer.recordPhraseStartIfNeeded(timestampSeconds: 1.0)

    let flushed = DuetPhraseBuffer.FlushResult(trimmedNotes: [], untrimmedEndTimeSeconds: 0.5, endTimeSeconds: 0.5)
    let events = buffer.flushPhrase(flushedPhrase: flushed)

    let ccAtZero: [(Int, Int)] = events
        .filter { $0.type == .cc }
        .filter { abs($0.time - 0.0) < 1e-9 }
        .compactMap { event in
            guard let controller = event.controller, let value = event.value else { return nil }
            return (controller, value)
        }
        .sorted { lhs, rhs in
            if lhs.0 != rhs.0 { return lhs.0 < rhs.0 }
            return lhs.1 < rhs.1
        }

    let snapshot = ccAtZero.map { "\($0.0):\($0.1)" }
    #expect(snapshot == ["7:80", "11:90", "64:127"])
}

@Test
func duetPhraseEventBufferInjectsCCStateAtWindowStartWhenTrimmingLongPhrase() {
    var buffer = DuetPhraseEventBuffer()
    buffer.recordPhraseStartIfNeeded(timestampSeconds: 100.0)
    buffer.recordControlChange(controller: 64, value: 127, timestampSeconds: 101.0) // outside the last-15s window

    // phraseEnd=40s -> windowStart=25s, the change at t=1s would normally be trimmed out.
    let flushedNotes = DuetPhraseBuffer.FlushResult(trimmedNotes: [], untrimmedEndTimeSeconds: 40.0, endTimeSeconds: 15.0)
    let events = buffer.flushPhrase(flushedPhrase: flushedNotes)

    #expect(events.count == 1)
    #expect(events[0].type == .cc)
    #expect(events[0].controller == 64)
    #expect(events[0].value == 127)
    #expect(abs(events[0].time - 0.0) < 1e-9)
}
