import Foundation
import ImprovProtocol
@testable import LonelyPianistAVP
import Testing

@Test
func duetPhraseBufferFlushComputesEndTimeAndDoesNotTrimWhenUnder10Seconds() {
    var buffer = DuetPhraseBuffer()
    buffer.recordNoteOn(midi: 60, velocity: 90, timestampSeconds: 1.0)
    buffer.recordNoteOff(midi: 60, timestampSeconds: 1.5)

    let flushed = buffer.flushPhrase(endTimestampSeconds: 1.5)
    #expect(flushed.trimmedNotes.count == 1)
    #expect(abs(flushed.endTimeSeconds - 0.5) < 1e-9)

    let policy = DuetPhrasePolicy.makeResult(from: flushed)
    #expect(abs(policy.desiredReplySeconds - 1.0) < 1e-9)
    #expect(abs(policy.desiredTotalDurationSeconds - 1.5) < 1e-9)
}

@Test
func duetPhraseBufferFlushTrimsLast15SecondsAndRebasesWhenOver10Seconds() {
    var buffer = DuetPhraseBuffer()
    buffer.recordNoteOn(midi: 60, velocity: 90, timestampSeconds: 100.0)
    buffer.recordNoteOff(midi: 60, timestampSeconds: 100.1)

    buffer.recordNoteOn(midi: 64, velocity: 90, timestampSeconds: 120.0)
    buffer.recordNoteOff(midi: 64, timestampSeconds: 120.2)

    let flushed = buffer.flushPhrase(endTimestampSeconds: 120.2)
    #expect(flushed.trimmedNotes.count == 1)
    #expect(flushed.trimmedNotes[0].note == 64)
    #expect(abs(flushed.trimmedNotes[0].time - 14.8) < 1e-9)
    #expect(abs(flushed.endTimeSeconds - 15.0) < 1e-9)

    let policy = DuetPhrasePolicy.makeResult(from: flushed)
    #expect(abs(policy.desiredReplySeconds - 8.0) < 1e-9)
}

@Test
func duetPhrasePolicyAdditionalSecondsClampsToRange() {
    func additional(endTime: TimeInterval) -> TimeInterval {
        DuetPhrasePolicy.makeResult(
            from: DuetPhraseBuffer.FlushResult(trimmedNotes: [], untrimmedEndTimeSeconds: endTime, endTimeSeconds: endTime)
        ).desiredReplySeconds
    }

    #expect(abs(additional(endTime: 0.5) - 1.0) < 1e-9)
    #expect(abs(additional(endTime: 1.0) - 1.0) < 1e-9)
    #expect(abs(additional(endTime: 8.0) - 8.0) < 1e-9)
    #expect(abs(additional(endTime: 10.0) - 8.0) < 1e-9)
    #expect(abs(additional(endTime: 30.0) - 8.0) < 1e-9)
}
