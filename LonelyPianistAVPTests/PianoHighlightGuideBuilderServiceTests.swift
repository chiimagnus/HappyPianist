@testable import LonelyPianistAVP
import Testing

@Test
func highlightGuideBuilderEmitsReleaseGapAndRetriggerForRepeatedNote() {
    let score = MusicXMLScore(notes: [
        makeNote(tick: 0, duration: 2, midi: 60),
        makeRest(tick: 2, duration: 2),
        makeNote(tick: 4, duration: 2, midi: 60),
    ])
    let steps = PracticeStepBuilder().buildSteps(from: score).steps
    let spans = MusicXMLNoteSpanBuilder().buildSpans(from: score.notes)

    let guides = PianoHighlightGuideBuilderService().buildGuides(
        input: PianoHighlightGuideBuildInput(score: score, steps: steps, noteSpans: spans)
    )

    let triggerGuides = guides.filter { $0.kind == .trigger }
    #expect(triggerGuides.count == 2)
    #expect(triggerGuides[0].highlightedMIDINotes == [60])
    #expect(triggerGuides[1].highlightedMIDINotes == [60])
    #expect(triggerGuides[0].id != triggerGuides[1].id)
    #expect(guides.contains { $0.tick == 2 && $0.highlightedMIDINotes.isEmpty })
}

@Test
func highlightGuideBuilderDoesNotRetriggerTieStopContinuation() {
    let score = MusicXMLScore(notes: [
        makeNote(tick: 0, duration: 2, midi: 60, tieStart: true),
        makeNote(tick: 2, duration: 2, midi: 60, tieStop: true),
    ])
    let steps = PracticeStepBuilder().buildSteps(from: score).steps
    let spans = MusicXMLNoteSpanBuilder().buildSpans(from: score.notes)

    let guides = PianoHighlightGuideBuilderService().buildGuides(
        input: PianoHighlightGuideBuildInput(score: score, steps: steps, noteSpans: spans)
    )

    #expect(guides.count(where: { $0.kind == .trigger }) == 1)
    #expect(guides.first?.highlightedMIDINotes == [60])
}

@Test
func highlightGuideBuilderGroupsChordInSingleTriggerGuide() {
    let score = MusicXMLScore(notes: [
        makeNote(tick: 0, duration: 2, midi: 60),
        makeNote(tick: 0, duration: 2, midi: 64, isChord: true),
        makeNote(tick: 0, duration: 2, midi: 67, isChord: true),
    ])
    let steps = PracticeStepBuilder().buildSteps(from: score).steps
    let spans = MusicXMLNoteSpanBuilder().buildSpans(from: score.notes)

    let guides = PianoHighlightGuideBuilderService().buildGuides(
        input: PianoHighlightGuideBuildInput(score: score, steps: steps, noteSpans: spans)
    )

    let trigger = guides.first { $0.kind == .trigger }
    #expect(trigger?.highlightedMIDINotes == [60, 64, 67])
    #expect(trigger?.triggeredNotes.count == 3)
}

@Test
func highlightGuideBuilderPreservesStaffAndVoiceOccurrences() {
    let score = MusicXMLScore(notes: [
        makeNote(tick: 0, duration: 2, midi: 60, staff: 1, voice: 1),
        makeNote(tick: 0, duration: 2, midi: 60, isChord: true, staff: 2, voice: 2),
    ])
    let steps = [PracticeStep(tick: 0, notes: [
        PracticeStepNote(midiNote: 60, staff: 1),
        PracticeStepNote(midiNote: 60, staff: 2),
    ])]
    let spans = MusicXMLNoteSpanBuilder().buildSpans(from: score.notes)

    let guides = PianoHighlightGuideBuilderService().buildGuides(
        input: PianoHighlightGuideBuildInput(score: score, steps: steps, noteSpans: spans)
    )

    let trigger = guides.first { $0.kind == .trigger }
    #expect(trigger?.triggeredNotes.count == 2)
    #expect(Set(trigger?.triggeredNotes.compactMap(\.staff) ?? []) == [1, 2])
}

private func makeNote(
    tick: Int,
    duration: Int,
    midi: Int,
    isChord: Bool = false,
    tieStart: Bool = false,
    tieStop: Bool = false,
    staff: Int = 1,
    voice: Int = 1,
    isGrace: Bool = false,
    graceSlash: Bool = false,
    graceStealTimePrevious: Double? = nil,
    graceStealTimeFollowing: Double? = nil,
    attackTicks: Int? = nil,
    releaseTicks: Int? = nil,
    articulations: Set<MusicXMLArticulation> = [],
    arpeggiate: MusicXMLArpeggiate? = nil
) -> MusicXMLNoteEvent {
    MusicXMLNoteEvent(
        partID: "P1",
        measureNumber: 1,
        tick: tick,
        durationTicks: duration,
        midiNote: midi,
        isRest: false,
        isChord: isChord,
        isGrace: isGrace,
        graceSlash: graceSlash,
        graceStealTimePrevious: graceStealTimePrevious,
        graceStealTimeFollowing: graceStealTimeFollowing,
        tieStart: tieStart,
        tieStop: tieStop,
        staff: staff,
        voice: voice,
        attackTicks: attackTicks,
        releaseTicks: releaseTicks,
        articulations: articulations,
        arpeggiate: arpeggiate
    )
}

private func makeRest(tick: Int, duration: Int) -> MusicXMLNoteEvent {
    MusicXMLNoteEvent(
        partID: "P1",
        measureNumber: 1,
        tick: tick,
        durationTicks: duration,
        midiNote: nil,
        isRest: true,
        isChord: false,
        tieStart: false,
        tieStop: false,
        staff: 1,
        voice: 1
    )
}

@Test
func highlightGuideBuilderPreservesSameMidiSameStaffDifferentVoices() {
    let score = MusicXMLScore(notes: [
        makeNote(tick: 0, duration: 2, midi: 60, staff: 1, voice: 1),
        makeNote(tick: 0, duration: 3, midi: 60, isChord: true, staff: 1, voice: 2),
    ])
    let steps = PracticeStepBuilder().buildSteps(from: score).steps
    let spans = MusicXMLNoteSpanBuilder().buildSpans(from: score.notes)

    let guides = PianoHighlightGuideBuilderService().buildGuides(
        input: PianoHighlightGuideBuildInput(score: score, steps: steps, noteSpans: spans)
    )

    let trigger = guides.first { $0.kind == .trigger }
    #expect(trigger?.triggeredNotes.count == 2)
    #expect(Set(trigger?.triggeredNotes.compactMap(\.voice) ?? []) == [1, 2])
    #expect(Set(trigger?.triggeredNotes.map(\.offTick) ?? []) == [2, 3])
}

@Test
func highlightGuideBuilderUsesArticulatedOffTickFromNoteSpans() {
    let score = MusicXMLScore(notes: [
        makeNote(tick: 0, duration: 480, midi: 60, articulations: [.staccato]),
    ])
    let steps = PracticeStepBuilder().buildSteps(from: score).steps
    let spans = MusicXMLNoteSpanBuilder().buildSpans(from: score.notes)

    let guides = PianoHighlightGuideBuilderService().buildGuides(
        input: PianoHighlightGuideBuildInput(score: score, steps: steps, noteSpans: spans)
    )

    let trigger = guides.first { $0.kind == .trigger }
    #expect(spans.count == 1)
    #expect(spans.first?.offTick == 240)
    #expect(trigger?.triggeredNotes.first?.offTick == spans.first?.offTick)
}

@Test
func highlightGuideBuilderUsesPerformanceTimingOnOffTicksWhenEnabled() {
    let score = MusicXMLScore(notes: [
        makeNote(tick: 0, duration: 480, midi: 60, attackTicks: 12, releaseTicks: 8),
    ])
    let steps = PracticeStepBuilder().buildSteps(from: score).steps
    let spans = MusicXMLNoteSpanBuilder().buildSpans(from: score.notes, performanceTimingEnabled: true)

    let guides = PianoHighlightGuideBuilderService().buildGuides(
        input: PianoHighlightGuideBuildInput(score: score, steps: steps, noteSpans: spans)
    )

    let trigger = guides.first { $0.kind == .trigger && $0.practiceStepIndex == 0 }
    #expect(spans.count == 1)
    #expect(trigger?.tick == spans.first?.onTick)
    #expect(trigger?.triggeredNotes.first?.onTick == spans.first?.onTick)
    #expect(trigger?.triggeredNotes.first?.offTick == spans.first?.offTick)
}

@Test
func highlightGuideBuilderUsesGraceScheduleWhenGraceEnabled() {
    var expressivity = MusicXMLExpressivityOptions()
    expressivity.graceEnabled = true
    let score = MusicXMLScore(notes: [
        makeNote(
            tick: 480,
            duration: 0,
            midi: 62,
            isGrace: true,
            graceStealTimeFollowing: 0.25
        ),
        makeNote(tick: 480, duration: 480, midi: 60),
    ])
    let steps = PracticeStepBuilder().buildSteps(from: score, expressivity: expressivity).steps
    let spans = MusicXMLNoteSpanBuilder().buildSpans(from: score.notes, expressivity: expressivity)

    let guides = PianoHighlightGuideBuilderService().buildGuides(
        input: PianoHighlightGuideBuildInput(score: score, steps: steps, noteSpans: spans, expressivity: expressivity)
    )

    let graceSpan = spans.first(where: { $0.midiNote == 62 })
    let mainSpan = spans.first(where: { $0.midiNote == 60 })
    let graceTrigger = guides.first { $0.kind == .trigger && $0.triggeredNotes.contains(where: { $0.midiNote == 62 }) }
    let mainTrigger = guides.first { $0.kind == .trigger && $0.triggeredNotes.contains(where: { $0.midiNote == 60 }) }

    #expect(spans.count == 2)
    #expect(graceTrigger?.tick == graceSpan?.onTick)
    #expect(graceTrigger?.triggeredNotes.first(where: { $0.midiNote == 62 })?.offTick == graceSpan?.offTick)
    #expect(mainTrigger?.tick == mainSpan?.onTick)
    #expect(mainTrigger?.triggeredNotes.first(where: { $0.midiNote == 60 })?.offTick == mainSpan?.offTick)
}

@Test
func highlightGuideBuilderUsesArpeggiateOffsetWhenEnabled() {
    var expressivity = MusicXMLExpressivityOptions()
    expressivity.arpeggiateEnabled = true
    let arp = MusicXMLArpeggiate(numberToken: nil, directionToken: nil)
    let score = MusicXMLScore(notes: [
        makeNote(tick: 0, duration: 480, midi: 60, arpeggiate: arp),
        makeNote(tick: 0, duration: 480, midi: 64, isChord: true, arpeggiate: arp),
    ])
    let steps = PracticeStepBuilder().buildSteps(from: score, expressivity: expressivity).steps
    let spans = MusicXMLNoteSpanBuilder().buildSpans(from: score.notes, expressivity: expressivity)

    let guides = PianoHighlightGuideBuilderService().buildGuides(
        input: PianoHighlightGuideBuildInput(score: score, steps: steps, noteSpans: spans, expressivity: expressivity)
    )

    let triggerTicks = Set(guides.filter { $0.kind == .trigger }.map(\.tick))
    let spanTicks = Set(spans.map(\.onTick))
    #expect(triggerTicks == spanTicks)
    #expect(triggerTicks.count == 2)
}

@Test
func highlightGuideBuilderUsesFermataExtraTicksWhenEnabled() {
    var expressivity = MusicXMLExpressivityOptions()
    expressivity.fermataEnabled = true
    let score = MusicXMLScore(notes: [
        makeNote(tick: 0, duration: 480, midi: 60),
    ], fermataEvents: [
        MusicXMLFermataEvent(
            tick: 0,
            scope: MusicXMLEventScope(partID: "P1", staff: 1, voice: nil),
            source: .noteNotations
        ),
    ])
    let fermataTimeline = MusicXMLFermataTimeline(fermataEvents: score.fermataEvents, notes: score.notes)
    let steps = PracticeStepBuilder().buildSteps(from: score, expressivity: expressivity).steps
    let spans = MusicXMLNoteSpanBuilder().buildSpans(
        from: score.notes,
        performanceTimingEnabled: false,
        expressivity: expressivity,
        fermataTimeline: fermataTimeline
    )

    let guides = PianoHighlightGuideBuilderService().buildGuides(
        input: PianoHighlightGuideBuildInput(score: score, steps: steps, noteSpans: spans, expressivity: expressivity)
    )

    let trigger = guides.first { $0.kind == .trigger }
    #expect(spans.count == 1)
    #expect(spans.first?.offTick == 720)
    #expect(trigger?.triggeredNotes.first?.offTick == spans.first?.offTick)
}
