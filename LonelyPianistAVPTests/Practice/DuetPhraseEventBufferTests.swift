import Foundation
import ImprovProtocol
@testable import LonelyPianistAVP
import Testing

@Test
func duetPhraseEventBufferSnapshotFiltersWhitelistAndRebasesWindow() {
    var buffer = DuetPhraseEventBuffer()
    buffer.recordControlChange(controller: 64, value: 127, timestampSeconds: 1.0)
    buffer.recordControlChange(controller: 7, value: 90, timestampSeconds: 1.2)
    buffer.recordControlChange(controller: 1, value: 80, timestampSeconds: 1.3) // ignored

    let snapshot = buffer.snapshot(nowTimestampSeconds: 1.5, lookbackSeconds: 4.0, maxPromptSeconds: 3.0)
    let summary = snapshot.promptEvents.compactMap { event -> String? in
        guard event.type == .cc, let controller = event.controller, let value = event.value else { return nil }
        return "\(controller):\(value)@\(String(format: "%.2f", event.time))"
    }

    #expect(summary == ["64:127@0.00", "7:90@0.20"])
    #expect(snapshot.latestValues[64] == 127)
    #expect(snapshot.latestValues[1] == nil)
    #expect(snapshot.sustainValue == 127)
}

@Test
func duetPhraseEventBufferInjectsInitialCCStateAtWindowStart() {
    var buffer = DuetPhraseEventBuffer()
    buffer.recordControlChange(controller: 64, value: 127, timestampSeconds: 0.5)
    buffer.recordControlChange(controller: 11, value: 70, timestampSeconds: 0.7)
    buffer.recordControlChange(controller: 64, value: 0, timestampSeconds: 2.6)

    let snapshot = buffer.snapshot(nowTimestampSeconds: 3.0, lookbackSeconds: 10.0, maxPromptSeconds: 1.0)
    let zeroTime = snapshot.promptEvents.filter { abs($0.time - 0.0) < 1e-9 }
    let zeroSummary = zeroTime.compactMap { event -> String? in
        guard let controller = event.controller, let value = event.value else { return nil }
        return "\(controller):\(value)"
    }.sorted()

    #expect(zeroSummary == ["11:70", "64:127"])
    #expect(snapshot.promptEvents.contains { $0.controller == 64 && $0.value == 0 && abs($0.time - 0.6) < 1e-9 })
}

@Test
func duetPhraseEventBufferPrunesOldHistory() {
    var buffer = DuetPhraseEventBuffer()
    buffer.recordControlChange(controller: 64, value: 127, timestampSeconds: 1.0)
    buffer.recordControlChange(controller: 7, value: 100, timestampSeconds: 15.0)

    let snapshot = buffer.snapshot(nowTimestampSeconds: 15.5, lookbackSeconds: 12.0, maxPromptSeconds: 3.0)
    #expect(snapshot.promptEvents.contains { $0.controller == 7 })
    #expect(snapshot.promptEvents.contains { $0.controller == 64 } == false)
}
