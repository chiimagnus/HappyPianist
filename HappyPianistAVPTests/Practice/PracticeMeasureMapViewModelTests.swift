@testable import HappyPianistAVP
import Testing

@Test
func measureMapDeduplicatesRepeatedSourceMeasures() {
    let source = PracticeSourceMeasureID(partID: "P1", sourceMeasureIndex: 0, sourceNumberToken: "1")
    let spans = [0, 1].map { occurrence in
        MusicXMLMeasureSpan(
            partID: source.partID,
            measureNumber: 1,
            sourceMeasureIndex: source.sourceMeasureIndex,
            sourceMeasureNumberToken: source.sourceNumberToken,
            occurrenceIndex: occurrence,
            startTick: occurrence * 10,
            endTick: occurrence * 10 + 10
        )
    }
    let map = PracticeMeasureMapViewModel(measureSpans: spans, progress: nil, handMode: .both, currentPassage: nil, currentMeasure: nil)
    #expect(map.items.count == 1)
    #expect(map.items[0].state == .notStarted)
}
