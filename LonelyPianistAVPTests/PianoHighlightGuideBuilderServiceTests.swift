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

    #expect(guides.filter { $0.kind == .trigger }.count == 1)
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
    voice: Int = 1
) -> MusicXMLNoteEvent {
    MusicXMLNoteEvent(
        partID: "P1",
        measureNumber: 1,
        tick: tick,
        durationTicks: duration,
        midiNote: midi,
        isRest: false,
        isChord: isChord,
        tieStart: tieStart,
        tieStop: tieStop,
        staff: staff,
        voice: voice
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
