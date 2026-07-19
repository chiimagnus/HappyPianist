@testable import HappyPianistAVP
import Testing

@Test
func highlightGuideBuilderEmitsReleaseGapAndRetriggerForRepeatedNote() {
    let score = MusicXMLScore(notes: [
        makeNote(tick: 0, duration: 2, midi: 60),
        makeRest(tick: 2, duration: 2),
        makeNote(tick: 4, duration: 2, midi: 60),
    ])
    let plan = makeTestScorePerformancePlan(from: score)

    let guides = PianoHighlightGuideBuilderService().buildGuides(plan: plan)

    let triggerGuides = guides.filter { $0.kind == .trigger }
    #expect(triggerGuides.count == 2)
    #expect(triggerGuides[0].highlightedMIDINotes == [60])
    #expect(triggerGuides[1].highlightedMIDINotes == [60])
    #expect(triggerGuides[0].triggeredNotes[0].occurrenceID != triggerGuides[1].triggeredNotes[0].occurrenceID)
    #expect(guides.contains { $0.tick == 2 && $0.highlightedMIDINotes.isEmpty })
}

@Test
func highlightGuideBuilderUsesPlanTieOccurrenceWithoutRetriggeringContinuation() throws {
    let score = MusicXMLScore(notes: [
        makeNote(tick: 0, duration: 2, midi: 60, ties: [makeTie("start")]),
        makeNote(tick: 2, duration: 2, midi: 60, ties: [makeTie("stop")]),
    ])
    let plan = makeTestScorePerformancePlan(from: score)

    let guides = PianoHighlightGuideBuilderService().buildGuides(plan: plan)

    let event = try #require(plan.noteEvents.first)
    let trigger = try #require(guides.first { $0.kind == .trigger })
    #expect(guides.count(where: { $0.kind == .trigger }) == 1)
    #expect(trigger.highlightedMIDINotes == [60])
    #expect(trigger.triggeredNotes[0].occurrenceID == event.id.description)
}

@Test
func highlightGuideBuilderGroupsPlanChordInSingleTriggerGuide() {
    let score = MusicXMLScore(notes: [
        makeNote(tick: 0, duration: 2, midi: 60),
        makeNote(tick: 0, duration: 2, midi: 64, isChord: true),
        makeNote(tick: 0, duration: 2, midi: 67, isChord: true),
    ])
    let plan = makeTestScorePerformancePlan(from: score)

    let guides = PianoHighlightGuideBuilderService().buildGuides(plan: plan)

    let trigger = guides.first { $0.kind == .trigger }
    #expect(trigger?.highlightedMIDINotes == [60, 64, 67])
    #expect(trigger?.triggeredNotes.count == 3)
    #expect(Set(trigger?.triggeredNotes.map(\.occurrenceID) ?? []).count == 3)
}

@Test
func highlightGuideBuilderPreservesSamePitchOccurrencesAndHands() throws {
    let score = MusicXMLScore(notes: [
        makeNote(tick: 0, duration: 2, midi: 60, staff: 1, voice: 1),
        makeNote(tick: 0, duration: 2, midi: 60, isChord: true, staff: 2, voice: 2),
    ])
    let rightID = try #require(score.notes[0].sourceID)
    let leftID = try #require(score.notes[1].sourceID)
    let plan = makeTestScorePerformancePlan(from: score, handAssignments: [
        rightID: ScoreHandAssignment(hand: .right, provenance: .score),
        leftID: ScoreHandAssignment(hand: .left, provenance: .score),
    ])

    let guides = PianoHighlightGuideBuilderService().buildGuides(plan: plan)

    let trigger = try #require(guides.first { $0.kind == .trigger })
    #expect(trigger.highlightedMIDINotes == [60])
    #expect(trigger.triggeredNotes.count == 2)
    #expect(Set(trigger.triggeredNotes.compactMap(\.staff)) == [1, 2])
    #expect(Set(trigger.triggeredNotes.map(\.hand)) == [.right, .left])
    #expect(Set(trigger.triggeredNotes.map(\.occurrenceID)) == Set(plan.noteEvents.map { $0.id.description }))
}

@Test
func highlightGuideBuilderKeepsPhysicalKeyLitUntilLastSamePitchVoiceReleases() throws {
    let score = MusicXMLScore(notes: [
        makeNote(tick: 0, duration: 2, midi: 60, staff: 1, voice: 1),
        makeNote(tick: 0, duration: 3, midi: 60, isChord: true, staff: 1, voice: 2),
    ])
    let plan = makeTestScorePerformancePlan(from: score)

    let guides = PianoHighlightGuideBuilderService().buildGuides(plan: plan)

    let trigger = try #require(guides.first { $0.kind == .trigger })
    let firstRelease = try #require(guides.first { $0.tick == 2 })
    let finalRelease = try #require(guides.first { $0.tick == 3 })
    #expect(trigger.triggeredNotes.count == 2)
    #expect(Set(trigger.triggeredNotes.compactMap(\.voice)) == [1, 2])
    #expect(Set(trigger.triggeredNotes.map(\.offTick)) == [2, 3])
    #expect(firstRelease.highlightedMIDINotes == [60])
    #expect(firstRelease.releasedMIDINotes.isEmpty)
    #expect(finalRelease.highlightedMIDINotes.isEmpty)
    #expect(finalRelease.releasedMIDINotes == [60])
}

@Test
func highlightGuideBuilderUsesPlanArticulatedOffTick() throws {
    let score = MusicXMLScore(notes: [
        makeNote(tick: 0, duration: 480, midi: 60, articulations: [.staccato]),
    ])
    let plan = makeTestScorePerformancePlan(from: score)

    let guides = PianoHighlightGuideBuilderService().buildGuides(plan: plan)

    let event = try #require(plan.noteEvents.first)
    let trigger = try #require(guides.first { $0.kind == .trigger })
    #expect(event.performedOffTick == 240)
    #expect(trigger.triggeredNotes.first?.offTick == event.performedOffTick)
}

@Test
func highlightGuideBuilderUsesPlanPerformanceTiming() throws {
    let score = MusicXMLScore(notes: [
        makeNote(tick: 0, duration: 480, midi: 60, attackTicks: 12, releaseTicks: 8),
    ])
    let plan = makeTestScorePerformancePlan(from: score, performanceTimingEnabled: true)

    let guides = PianoHighlightGuideBuilderService().buildGuides(plan: plan)

    let event = try #require(plan.noteEvents.first)
    let trigger = try #require(guides.first { $0.kind == .trigger })
    #expect(trigger.tick == event.performedOnTick)
    #expect(trigger.triggeredNotes.first?.onTick == event.performedOnTick)
    #expect(trigger.triggeredNotes.first?.offTick == event.performedOffTick)
}

@Test
func highlightGuideBuilderUsesPlanGraceSchedule() throws {
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
    let plan = makeTestScorePerformancePlan(from: score, expressivity: expressivity)

    let guides = PianoHighlightGuideBuilderService().buildGuides(plan: plan)

    for event in plan.noteEvents {
        let note = try #require(guides.flatMap(\.triggeredNotes).first { $0.occurrenceID == event.id.description })
        #expect(note.onTick == event.performedOnTick)
        #expect(note.offTick == event.performedOffTick)
    }
}

@Test
func highlightGuideBuilderUsesPlanArpeggiateOffsets() {
    var expressivity = MusicXMLExpressivityOptions()
    expressivity.arpeggiateEnabled = true
    let arpeggiate = MusicXMLArpeggiate(numberToken: nil, directionToken: nil)
    let score = MusicXMLScore(notes: [
        makeNote(tick: 0, duration: 480, midi: 60, arpeggiate: arpeggiate),
        makeNote(tick: 0, duration: 480, midi: 64, isChord: true, arpeggiate: arpeggiate),
    ])
    let plan = makeTestScorePerformancePlan(from: score, expressivity: expressivity)

    let guides = PianoHighlightGuideBuilderService().buildGuides(plan: plan)

    let triggerTicks = Set(guides.filter { $0.kind == .trigger }.map(\.tick))
    #expect(triggerTicks == Set(plan.noteEvents.map(\.performedOnTick)))
    #expect(triggerTicks.count == 2)
}

private func makeNote(
    tick: Int,
    duration: Int,
    midi: Int,
    isChord: Bool = false,
    ties: [MusicXMLTie] = [],
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
        sourceID: MusicXMLSourceNoteID(
            partID: "P1",
            sourceMeasureIndex: 0,
            sourceMeasureNumberToken: "1",
            staff: staff,
            voice: voice,
            sourceOrdinal: tick * 1_000_000 + midi * 1_000 + staff * 100 + voice
        ),
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
        ties: ties,
        staff: staff,
        voice: voice,
        attackTicks: attackTicks,
        releaseTicks: releaseTicks,
        articulations: articulations,
        arpeggiate: arpeggiate
    )
}

private func makeTie(_ typeToken: String) -> MusicXMLTie {
    MusicXMLTie(
        sourceID: nil,
        sourceElement: .notation,
        typeToken: typeToken,
        numberToken: nil,
        placementToken: nil
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
        staff: 1,
        voice: 1
    )
}
