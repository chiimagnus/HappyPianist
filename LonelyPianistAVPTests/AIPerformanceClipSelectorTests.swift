@testable import LonelyPianistAVP
import Testing

@Test
func selectorReturnsNextTwoMeasuresRange() {
    let spans = [
        MusicXMLMeasureSpan(partID: "P1", measureNumber: 0, startTick: 0, endTick: 100),
        MusicXMLMeasureSpan(partID: "P1", measureNumber: 1, startTick: 100, endTick: 200),
        MusicXMLMeasureSpan(partID: "P1", measureNumber: 2, startTick: 200, endTick: 300),
    ]

    let selector = AIPerformanceClipSelector()
    let range = selector.tickRange(currentTick: 10, measureSpans: spans)
    #expect(range?.startTick == 100)
    #expect(range?.endTick == 300)
}

@Test
func selectorPlaysWhateverRemainsWhenLessThanTwoMeasuresRemain() {
    let spans = [
        MusicXMLMeasureSpan(partID: "P1", measureNumber: 0, startTick: 0, endTick: 100),
        MusicXMLMeasureSpan(partID: "P1", measureNumber: 1, startTick: 100, endTick: 200),
    ]

    let selector = AIPerformanceClipSelector()
    let range = selector.tickRange(currentTick: 10, measureSpans: spans)
    #expect(range?.startTick == 100)
    #expect(range?.endTick == 200)
}

@Test
func selectorReturnsNilWhenThereIsNoNextMeasure() {
    let spans = [
        MusicXMLMeasureSpan(partID: "P1", measureNumber: 0, startTick: 0, endTick: 100),
    ]

    let selector = AIPerformanceClipSelector()
    #expect(selector.tickRange(currentTick: 10, measureSpans: spans) == nil)
}

@Test
func selectorReturnsNilWhenCurrentTickIsOutsideAllMeasures() {
    let spans = [
        MusicXMLMeasureSpan(partID: "P1", measureNumber: 0, startTick: 0, endTick: 100),
        MusicXMLMeasureSpan(partID: "P1", measureNumber: 1, startTick: 100, endTick: 200),
    ]

    let selector = AIPerformanceClipSelector()
    #expect(selector.tickRange(currentTick: -1, measureSpans: spans) == nil)
    #expect(selector.tickRange(currentTick: 250, measureSpans: spans) == nil)
}

@Test
func selectorSortsMeasureSpansBeforeSelecting() {
    let spans = [
        MusicXMLMeasureSpan(partID: "P1", measureNumber: 2, startTick: 200, endTick: 300),
        MusicXMLMeasureSpan(partID: "P1", measureNumber: 0, startTick: 0, endTick: 100),
        MusicXMLMeasureSpan(partID: "P1", measureNumber: 1, startTick: 100, endTick: 200),
    ]

    let selector = AIPerformanceClipSelector()
    let range = selector.tickRange(currentTick: 10, measureSpans: spans)
    #expect(range?.startTick == 100)
    #expect(range?.endTick == 300)
}

@Test
func selectorReturnsNilForInvalidTickRange() {
    let spans = [
        MusicXMLMeasureSpan(partID: "P1", measureNumber: 0, startTick: 0, endTick: 100),
        MusicXMLMeasureSpan(partID: "P1", measureNumber: 1, startTick: 100, endTick: 100),
    ]

    let selector = AIPerformanceClipSelector()
    #expect(selector.tickRange(currentTick: 10, measureSpans: spans) == nil)
}

