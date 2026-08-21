import Foundation
import MusicXML
@testable import Practice
import Testing

@Test
func contactTimelineUsesScheduledEventSecondsForChordsRepeatsLeadInAndPause() throws {
    let first = performanceNote(
        ordinal: 0,
        midiNote: 60,
        onTick: 100,
        offTick: 200,
        fingerings: [MusicXMLFingering(text: "3", provenance: .score)]
    )
    let chord = performanceNote(ordinal: 1, midiNote: 64, onTick: 100, offTick: 200)
    let repeated = performanceNote(ordinal: 2, midiNote: 60, onTick: 300, offTick: 400)
    let plan = performancePlan(notes: [first, chord, repeated])
    let firstGuide = guide(
        id: 10,
        tick: 100,
        stepIndex: 0,
        triggered: [highlightNote(for: first), highlightNote(for: chord)]
    )
    let repeatedGuide = guide(
        id: 20,
        tick: 300,
        stepIndex: 1,
        triggered: [highlightNote(for: repeated)]
    )
    let timeline = AutoplayPerformanceTimeline(events: [
        .init(id: 0, tick: 100, kind: .pauseSeconds(0.4)),
        .init(id: 1, sourceEventID: first.id.description, tick: 100, kind: .noteOn(midi: 60, velocity: 96)),
        .init(id: 2, sourceEventID: chord.id.description, tick: 100, kind: .noteOn(midi: 64, velocity: 96)),
        .init(id: 3, tick: 100, kind: .advanceStep(index: 0)),
        .init(id: 4, tick: 100, kind: .advanceGuide(index: 0, guideID: 10)),
        .init(id: 5, sourceEventID: first.id.description, tick: 200, kind: .noteOff(midi: 60)),
        .init(id: 6, sourceEventID: chord.id.description, tick: 200, kind: .noteOff(midi: 64)),
        .init(id: 7, sourceEventID: repeated.id.description, tick: 300, kind: .noteOn(midi: 60, velocity: 96)),
        .init(id: 8, tick: 300, kind: .advanceStep(index: 1)),
        .init(id: 9, tick: 300, kind: .advanceGuide(index: 1, guideID: 20)),
        .init(id: 10, sourceEventID: repeated.id.description, tick: 400, kind: .noteOff(midi: 60)),
    ])
    let schedule = schedule(for: timeline, leadInSeconds: 0.25)

    let contacts = PianoKeyContactTimeline(
        plan: plan,
        timeline: timeline,
        schedule: schedule,
        guideProjection: [firstGuide, repeatedGuide],
        stepProjection: [PracticeStep(tick: 100, notes: []), PracticeStep(tick: 300, notes: [])]
    )

    #expect(contacts.contacts.count == 3)
    let firstContact = try #require(contacts.contact(forOccurrenceID: first.id.description))
    let chordContact = try #require(contacts.contact(forOccurrenceID: chord.id.description))
    let repeatedContact = try #require(contacts.contact(forOccurrenceID: repeated.id.description))
    #expect(abs(try #require(firstContact.onsetSeconds) - 1.65) < 0.000_001)
    #expect(abs(try #require(firstContact.releaseSeconds) - 2.65) < 0.000_001)
    #expect(chordContact.onsetSeconds == firstContact.onsetSeconds)
    #expect(firstContact.guideID == 10)
    #expect(firstContact.stepIndex == 0)
    #expect(firstContact.staff == 1)
    #expect(firstContact.fingerings.map(\.text) == ["3"])
    #expect(repeatedContact.guideID == 20)
    #expect(repeatedContact.stepIndex == 1)
    #expect(repeatedContact.occurrenceID != firstContact.occurrenceID)
    #expect(repeatedContact.midiNote == firstContact.midiNote)
}

@Test
func contactTimelineMarksRangeStartHeldNotesWithoutRecomputingTheirOriginalOnset() throws {
    let held = performanceNote(ordinal: 0, midiNote: 48, onTick: 0, offTick: 300, hand: .left)
    let plan = performancePlan(notes: [held])
    let heldGuide = guide(
        id: 42,
        tick: 100,
        stepIndex: 0,
        active: [highlightNote(for: held)]
    )
    let timeline = AutoplayPerformanceTimeline(events: [
        .init(id: 0, sourceEventID: held.id.description, tick: 100, kind: .noteOn(midi: 48, velocity: 96)),
        .init(id: 1, tick: 100, kind: .advanceStep(index: 0)),
        .init(id: 2, tick: 100, kind: .advanceGuide(index: 0, guideID: 42)),
        .init(id: 3, sourceEventID: held.id.description, tick: 300, kind: .noteOff(midi: 48)),
    ])

    let contacts = PianoKeyContactTimeline(
        plan: plan,
        timeline: timeline,
        schedule: schedule(for: timeline, leadInSeconds: 0.1),
        guideProjection: [heldGuide],
        stepProjection: [PracticeStep(tick: 100, notes: [])]
    )
    let contact = try #require(contacts.contacts.first)

    #expect(contact.carriedIn)
    #expect(contact.staff == 2)
    #expect(contact.guideID == 42)
    #expect(contact.stepIndex == 0)
    #expect(abs(try #require(contact.onsetSeconds) - 1.1) < 0.000_001)
    #expect(abs(try #require(contact.releaseSeconds) - 3.1) < 0.000_001)
}

@Test
func contactTimelineKeepsIncompleteTimelinePairsExplicitlyUnplannable() throws {
    let missingOff = performanceNote(ordinal: 0, midiNote: 60, onTick: 100, offTick: 200)
    let missingOn = performanceNote(ordinal: 1, midiNote: 64, onTick: 100, offTick: 200)
    let plan = performancePlan(notes: [missingOff, missingOn])
    let timeline = AutoplayPerformanceTimeline(events: [
        .init(id: 0, sourceEventID: missingOff.id.description, tick: 100, kind: .noteOn(midi: 60, velocity: 96)),
        .init(id: 1, sourceEventID: missingOn.id.description, tick: 200, kind: .noteOff(midi: 64)),
    ])

    let contacts = PianoKeyContactTimeline(
        plan: plan,
        timeline: timeline,
        schedule: schedule(for: timeline),
        guideProjection: [],
        stepProjection: []
    )
    let missingOffContact = try #require(contacts.contact(forOccurrenceID: missingOff.id.description))
    let missingOnContact = try #require(contacts.contact(forOccurrenceID: missingOn.id.description))

    #expect(missingOffContact.timing == .unplannable(.missingNoteOff))
    #expect(missingOnContact.timing == .unplannable(.missingNoteOn))
    #expect(missingOffContact.onsetSeconds == nil)
    #expect(missingOnContact.releaseSeconds == nil)
}

private func schedule(
    for timeline: AutoplayPerformanceTimeline,
    leadInSeconds: TimeInterval = 0
) -> AutoplayTimelineTimeSchedule {
    AutoplayTimelineTimeSchedule(
        timeline: timeline,
        tickToSeconds: { Double($0) / 100 },
        startTick: 0,
        leadInSeconds: leadInSeconds
    )
}

private func performancePlan(notes: [ScorePerformanceNoteEvent]) -> ScorePerformancePlan {
    ScorePerformancePlan(
        id: ScorePerformancePlanID(rawValue: "piano-key-contact-timeline"),
        sourceScoreIdentity: ScorePerformanceSourceIdentity(
            songID: UUID(),
            scoreRevision: "test",
            logicalInstrumentID: "piano"
        ),
        order: MusicXMLOrderSelection(requested: .written, applied: .written),
        resolution: ScorePerformanceTickResolution(ticksPerQuarter: 480),
        noteEvents: notes,
        tempoEvents: [],
        controllerEvents: [],
        annotations: [],
        approximations: []
    )
}

private func performanceNote(
    ordinal: Int,
    midiNote: Int,
    onTick: Int,
    offTick: Int,
    hand: ScoreHand = .right,
    fingerings: [MusicXMLFingering] = []
) -> ScorePerformanceNoteEvent {
    let sourceNoteID = MusicXMLSourceNoteID(
        partID: "P1",
        sourceMeasureIndex: 0,
        sourceMeasureNumberToken: "1",
        staff: hand == .left ? 2 : 1,
        voice: 1,
        sourceOrdinal: ordinal
    )
    let performedNoteID = MusicXMLPerformedNoteID(sourceID: sourceNoteID, occurrenceIndex: 0)
    return ScorePerformanceNoteEvent(
        id: ScorePerformanceNoteEventID(performedNoteID: performedNoteID, generatedOrdinal: nil),
        sourceNoteID: sourceNoteID,
        performedNoteID: performedNoteID,
        contributingSourceNoteIDs: [sourceNoteID],
        contributingPerformedNoteIDs: [performedNoteID],
        purpose: .source,
        writtenOnTick: onTick,
        writtenOffTick: offTick,
        performedOnTick: onTick,
        performedOffTick: offTick,
        writtenPitch: nil,
        midiNote: midiNote,
        velocityResolution: ScorePerformanceVelocityResolution(
            baseVelocity: 96,
            curveVelocity: nil,
            articulationDelta: 0,
            unclampedVelocity: 96,
            velocity: 96,
            usesGenericDynamicBaseline: false
        ),
        staff: hand == .left ? 2 : 1,
        voice: 1,
        handAssignment: ScoreHandAssignment(hand: hand, provenance: .score),
        fingerings: fingerings,
        timingProvenance: []
    )
}

private func highlightNote(for event: ScorePerformanceNoteEvent) -> PianoHighlightNote {
    PianoHighlightNote(
        occurrenceID: event.id.description,
        midiNote: event.midiNote,
        staff: event.staff,
        voice: event.voice,
        velocity: event.velocity,
        onTick: event.performedOnTick,
        offTick: event.performedOffTick,
        fingerings: event.fingerings,
        handAssignment: event.handAssignment
    )
}

private func guide(
    id: Int,
    tick: Int,
    stepIndex: Int,
    active: [PianoHighlightNote] = [],
    triggered: [PianoHighlightNote] = []
) -> PianoHighlightGuide {
    PianoHighlightGuide(
        id: id,
        kind: triggered.isEmpty ? .sustain : .trigger,
        tick: tick,
        durationTicks: nil,
        practiceStepIndex: stepIndex,
        activeNotes: active,
        triggeredNotes: triggered,
        releasedMIDINotes: []
    )
}
