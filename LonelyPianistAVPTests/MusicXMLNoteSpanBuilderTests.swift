@testable import LonelyPianistAVP
import Testing

@Test
func noteSpanBuilderMergesTieChainIntoSingleSpan() {
    let builder = MusicXMLNoteSpanBuilder()
    let notes: [MusicXMLNoteEvent] = [
        MusicXMLNoteEvent(
            partID: "P1",
            measureNumber: 1,
            tick: 0,
            durationTicks: 480,
            midiNote: 60,
            isRest: false,
            isChord: false,
            tieStart: true,
            tieStop: false,
            staff: 1,
            voice: 1
        ),
        MusicXMLNoteEvent(
            partID: "P1",
            measureNumber: 1,
            tick: 480,
            durationTicks: 480,
            midiNote: 60,
            isRest: false,
            isChord: false,
            tieStart: true,
            tieStop: true,
            staff: 1,
            voice: 1
        ),
        MusicXMLNoteEvent(
            partID: "P1",
            measureNumber: 1,
            tick: 960,
            durationTicks: 480,
            midiNote: 60,
            isRest: false,
            isChord: false,
            tieStart: false,
            tieStop: true,
            staff: 1,
            voice: 1
        ),
    ]

    let spans = builder.buildSpans(from: notes)
    #expect(spans.count == 1)
    #expect(spans[0].midiNote == 60)
    #expect(spans[0].onTick == 0)
    #expect(spans[0].offTick == 1440)
}

@Test
func noteSpanBuilderSkipsRestsAndBuildsNormalSpans() {
    let builder = MusicXMLNoteSpanBuilder()
    let notes: [MusicXMLNoteEvent] = [
        MusicXMLNoteEvent(
            partID: "P1",
            measureNumber: 1,
            tick: 0,
            durationTicks: 480,
            midiNote: nil,
            isRest: true,
            isChord: false,
            tieStart: false,
            tieStop: false,
            staff: 1,
            voice: 1
        ),
        MusicXMLNoteEvent(
            partID: "P1",
            measureNumber: 1,
            tick: 0,
            durationTicks: 480,
            midiNote: 64,
            isRest: false,
            isChord: false,
            tieStart: false,
            tieStop: false,
            staff: 1,
            voice: 1
        ),
    ]

    let spans = builder.buildSpans(from: notes)
    #expect(spans.count == 1)
    #expect(spans[0].midiNote == 64)
    #expect(spans[0].onTick == 0)
    #expect(spans[0].offTick == 480)
}

@Test
func noteSpanBuilderAppliesAttackAndReleaseWhenEnabled() {
    let builder = MusicXMLNoteSpanBuilder()
    let notes: [MusicXMLNoteEvent] = [
        MusicXMLNoteEvent(
            partID: "P1",
            measureNumber: 1,
            tick: 0,
            durationTicks: 480,
            midiNote: 60,
            isRest: false,
            isChord: false,
            tieStart: false,
            tieStop: false,
            staff: 1,
            voice: 1,
            attackTicks: 120,
            releaseTicks: 120
        ),
    ]

    let normal = builder.buildSpans(from: notes)
    #expect(normal.first?.onTick == 0)
    #expect(normal.first?.offTick == 480)

    let performance = builder.buildSpans(from: notes, performanceTimingEnabled: true)
    #expect(performance.first?.onTick == 120)
    #expect(performance.first?.offTick == 600)
}

@Test
func noteSpanBuilderShortensDurationForStaccato() {
    let builder = MusicXMLNoteSpanBuilder()
    let notes: [MusicXMLNoteEvent] = [
        MusicXMLNoteEvent(
            partID: "P1",
            measureNumber: 1,
            tick: 0,
            durationTicks: 480,
            midiNote: 60,
            isRest: false,
            isChord: false,
            tieStart: false,
            tieStop: false,
            staff: 1,
            voice: 1,
            articulations: [.staccato]
        ),
    ]

    let spans = builder.buildSpans(from: notes)
    #expect(spans.count == 1)
    #expect(spans[0].onTick == 0)
    #expect(spans[0].offTick == 240)
}
