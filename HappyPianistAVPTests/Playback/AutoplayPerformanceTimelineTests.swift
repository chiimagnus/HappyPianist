import Foundation
@testable import HappyPianistAVP
import Testing

@Test
func autoplayTimelineUsesPlanForSoundAndProjectionsOnlyForNavigation() throws {
    let plan = makeTimelinePlan(notes: [
        TestScorePerformanceNote(midiNote: 60, velocity: 80, onTick: 120, offTick: 360),
    ])
    let guide = makeTimelineGuide(id: 1, tick: 120)
    let step = PracticeStep(
        tick: 120,
        notes: [PracticeStepNote(midiNote: 99, staff: 1, handAssignment: .unknown)]
    )

    let timeline = AutoplayPerformanceTimeline.build(
        plan: plan,
        guideProjection: [guide],
        stepProjection: [step],
        tempoMap: MusicXMLTempoMap(tempoEvents: []),
        practiceHandMode: .both
    )

    let eventID = try #require(plan.noteEvents.first?.id.description)
    #expect(timeline.events.map(\.tick) == [120, 120, 120, 360])
    #expect(timeline.events.contains { event in
        event.sourceEventID == eventID && event.kind == .noteOn(midi: 60, velocity: 80)
    })
    #expect(timeline.events.contains { event in
        event.sourceEventID == eventID && event.kind == .noteOff(midi: 60)
    })
    #expect(timeline.events.contains { $0.kind == .advanceGuide(index: 0, guideID: 1) })
    #expect(timeline.events.contains { if case .noteOn(midi: 99, _) = $0.kind { true } else { false } } == false)
}

@Test
func autoplayTimelinePreservesSamePitchPlanEventsAndIdentities() {
    let plan = makeTimelinePlan(notes: [
        TestScorePerformanceNote(midiNote: 60, velocity: 70, onTick: 0, offTick: 120, voice: 1),
        TestScorePerformanceNote(midiNote: 60, velocity: 96, onTick: 0, offTick: 240, voice: 2),
    ])

    let timeline = makeTimeline(plan: plan)
    let noteOns = timeline.events.filter { if case .noteOn = $0.kind { true } else { false } }
    let noteOffs = timeline.events.filter { if case .noteOff = $0.kind { true } else { false } }

    #expect(plan.noteEvents.map(\.voice) == [1, 2])
    #expect(Set(plan.noteEvents.map(\.sourceNoteID)).count == 2)
    #expect(noteOns.map(\.kind) == [
        .noteOn(midi: 60, velocity: 70),
        .noteOn(midi: 60, velocity: 96),
    ])
    #expect(noteOns.count == 2)
    #expect(noteOffs.map(\.tick) == [120, 240])
    #expect(Set(noteOns.compactMap(\.sourceEventID)).count == 2)
    #expect(Set(noteOffs.compactMap(\.sourceEventID)) == Set(noteOns.compactMap(\.sourceEventID)))
}

@Test
func autoplayTimelineRetriggersOverlappingSamePitchWhileSustainIsDown() {
    let plan = makeTimelinePlan(
        notes: [
            TestScorePerformanceNote(midiNote: 60, velocity: 80, onTick: 0, offTick: 480),
            TestScorePerformanceNote(midiNote: 60, velocity: 88, onTick: 240, offTick: 720),
        ],
        controllerEvents: [timelineController(sourceID: directionID(ordinal: 8), tick: 0, value: 127)]
    )

    let midiEvents = makeTimeline(plan: plan).events.compactMap { event -> String? in
        switch event.kind {
        case let .controlChange(controller, value): "cc:\(controller):\(value)@\(event.tick)"
        case let .noteOn(midi, _): "on:\(midi)@\(event.tick)"
        case let .noteOff(midi): "off:\(midi)@\(event.tick)"
        default: nil
        }
    }

    #expect(midiEvents == ["cc:64:127@0", "on:60@0", "off:60@240", "on:60@240", "off:60@720"])
}

@Test
func autoplayTimelineKeepsZeroGapRepeatInOffThenOnOrder() {
    let plan = makeTimelinePlan(notes: [
        TestScorePerformanceNote(midiNote: 60, velocity: 80, onTick: 0, offTick: 240),
        TestScorePerformanceNote(midiNote: 60, velocity: 88, onTick: 240, offTick: 480),
    ])

    let eventsAtRetrigger = makeTimeline(plan: plan).events.filter { $0.tick == 240 }

    #expect(eventsAtRetrigger.map(\.kind) == [
        .noteOff(midi: 60),
        .noteOn(midi: 60, velocity: 88),
    ])
    #expect(eventsAtRetrigger.map(\.sourceEventID) == [
        plan.noteEvents[0].id.description,
        plan.noteEvents[1].id.description,
    ])
}

@Test
func transportReducerReportsStaleOffPreventionForRetrigger() {
    let plan = makeTimelinePlan(notes: [
        TestScorePerformanceNote(midiNote: 60, velocity: 80, onTick: 0, offTick: 480),
        TestScorePerformanceNote(midiNote: 60, velocity: 88, onTick: 240, offTick: 720),
    ])
    let notes = plan.noteEvents.map {
        PerformanceTransportReducer.Note(
            eventID: $0.id,
            midiNote: $0.midiNote,
            velocity: $0.velocity,
            onTick: $0.performedOnTick,
            offTick: $0.performedOffTick
        )
    }

    let reduction = PerformanceTransportReducer().reduce(notes: notes)

    #expect(reduction.retriggeredEventCount == 1)
    #expect(reduction.preventedStaleOffCount == 1)
    #expect(reduction.orphanOffCount == 0)
}

@Test
func autoplayTimelineKeepsZeroDurationPlanNotesReleasable() {
    let plan = makeTimelinePlan(notes: [
        TestScorePerformanceNote(midiNote: 60, velocity: 80, onTick: 0, offTick: 0),
    ])

    let midiEvents = makeTimeline(plan: plan).events.compactMap { event -> String? in
        switch event.kind {
        case let .noteOn(midi, _): "on:\(midi)@\(event.tick)"
        case let .noteOff(midi): "off:\(midi)@\(event.tick)"
        default: nil
        }
    }

    #expect(midiEvents == ["on:60@0", "off:60@1"])
}

@Test
func autoplayTimelinePreservesControllerReleaseAndRedownIdentity() {
    let upID = directionID(ordinal: 1)
    let downID = directionID(ordinal: 2)
    let plan = makeTimelinePlan(
        notes: [TestScorePerformanceNote(midiNote: 60, velocity: 80, onTick: 0, offTick: 480)],
        controllerEvents: [
            timelineController(sourceID: upID, tick: 480, value: 0),
            timelineController(sourceID: downID, tick: 480, value: 127),
        ]
    )

    let controllers = makeTimeline(plan: plan).events.filter {
        if case .controlChange = $0.kind { true } else { false }
    }

    #expect(controllers.map(\.kind) == [
        .controlChange(controller: 64, value: 0),
        .controlChange(controller: 64, value: 127),
    ])
    #expect(controllers.map(\.sourceEventID) == [upID.description, downID.description])
}

@Test
func autoplayTimelineCarriesTempoIdentity() {
    let sourceID = directionID(ordinal: 3)
    let plan = makeTimelinePlan(
        notes: [],
        tempoEvents: [ScorePerformanceTempoEvent(
            sourceDirectionID: sourceID,
            performedOccurrenceIndex: 0,
            tick: 0,
            quarterBPM: 96,
            endTick: 480,
            endQuarterBPM: 72
        )]
    )

    let event = makeTimeline(plan: plan).events.first
    #expect(event?.sourceEventID == sourceID.description)
    #expect(event?.kind == .tempo(quarterBPM: 96, endTick: 480, endQuarterBPM: 72))
}

@Test
func autoplayTimelineFiltersPlanEventsByHand() {
    let plan = makeTimelinePlan(notes: [
        TestScorePerformanceNote(
            midiNote: 48,
            velocity: 80,
            onTick: 0,
            offTick: 240,
            handAssignment: ScoreHandAssignment(hand: .left, provenance: .score)
        ),
        TestScorePerformanceNote(
            midiNote: 72,
            velocity: 80,
            onTick: 0,
            offTick: 240,
            handAssignment: ScoreHandAssignment(hand: .right, provenance: .score)
        ),
    ])

    let timeline = makeTimeline(plan: plan, practiceHandMode: .right)
    let soundingMIDIs = timeline.events.compactMap { event -> Int? in
        if case let .noteOn(midi, _) = event.kind { midi } else { nil }
    }

    #expect(soundingMIDIs == [72])
}

@Test
func autoplayTimelineExcludesControllerAtActiveRangeUpperBound() throws {
    let activeRange = try timelineActiveRange()
    let plan = makeTimelinePlan(
        notes: [TestScorePerformanceNote(midiNote: 60, velocity: 80, onTick: 0, offTick: 480)],
        controllerEvents: [timelineController(sourceID: directionID(ordinal: 4), tick: 480, value: 127)]
    )

    let timeline = makeTimeline(plan: plan, activeRange: activeRange)

    #expect(timeline.events.contains { event in
        guard event.tick == 480 else { return false }
        if case .controlChange = event.kind { return true }
        return false
    } == false)
}

@Test
func autoplayTimelineRestoresControllerStateAtActiveRangeStartWithoutDuplicatingAnExplicitEvent() throws {
    let activeRange = try timelineActiveRange(startTick: 480, endTick: 960)
    let carriedID = directionID(ordinal: 5)
    let explicitID = directionID(ordinal: 6)
    let plan = makeTimelinePlan(
        notes: [],
        controllerEvents: [
            timelineController(sourceID: carriedID, tick: 0, value: 127),
            timelineController(sourceID: explicitID, tick: 480, value: 0),
        ]
    )

    let controllers = makeTimeline(plan: plan, activeRange: activeRange).events.filter {
        if case .controlChange = $0.kind { true } else { false }
    }

    #expect(controllers.count == 1)
    #expect(controllers.first?.sourceEventID == explicitID.description)
    #expect(controllers.first?.kind == .controlChange(controller: 64, value: 0))
}

@Test
func autoplayTimelineInterpolatesTempoRampAtActiveRangeStart() throws {
    let activeRange = try timelineActiveRange(startTick: 480, endTick: 960)
    let sourceID = directionID(ordinal: 7)
    let plan = makeTimelinePlan(
        notes: [],
        tempoEvents: [ScorePerformanceTempoEvent(
            sourceDirectionID: sourceID,
            performedOccurrenceIndex: 0,
            tick: 0,
            quarterBPM: 120,
            endTick: 960,
            endQuarterBPM: 60
        )]
    )

    let tempo = makeTimeline(plan: plan, activeRange: activeRange).events.first

    #expect(tempo?.sourceEventID == sourceID.description)
    #expect(tempo?.kind == .tempo(quarterBPM: 90, endTick: 960, endQuarterBPM: 60))
}

@Test
func autoplayTimelineReconstructsCrossBoundaryHeldNoteWithoutRevivingBoundaryOff() throws {
    let activeRange = try timelineActiveRange(startTick: 480, endTick: 960)
    let plan = makeTimelinePlan(notes: [
        TestScorePerformanceNote(midiNote: 60, velocity: 72, onTick: 0, offTick: 720),
        TestScorePerformanceNote(midiNote: 62, velocity: 80, onTick: 0, offTick: 480),
        TestScorePerformanceNote(midiNote: 64, velocity: 88, onTick: 480, offTick: 720),
    ])

    let timeline = makeTimeline(plan: plan, activeRange: activeRange)
    let soundEvents = timeline.events.filter {
        if case .noteOn = $0.kind { return true }
        if case .noteOff = $0.kind { return true }
        return false
    }

    #expect(soundEvents.map(\.kind) == [
        .noteOn(midi: 60, velocity: 72),
        .noteOn(midi: 64, velocity: 88),
        .noteOff(midi: 60),
        .noteOff(midi: 64),
    ])
    #expect(soundEvents.map(\.tick) == [480, 480, 720, 720])
    #expect(soundEvents.contains { event in
        event.sourceEventID == plan.noteEvents[1].id.description
    } == false)
    #expect(timeline.rangeStartApproximations == [
        .reattackedHeldNote(eventID: plan.noteEvents[0].id),
    ])
}

@Test
func autoplayTimelinePrefersExplicitTempoAtActiveRangeStart() throws {
    let activeRange = try timelineActiveRange(startTick: 480, endTick: 960)
    let carriedID = directionID(ordinal: 9)
    let explicitID = directionID(ordinal: 10)
    let plan = makeTimelinePlan(
        notes: [],
        tempoEvents: [
            ScorePerformanceTempoEvent(
                sourceDirectionID: carriedID,
                performedOccurrenceIndex: 0,
                tick: 0,
                quarterBPM: 120,
                endTick: nil,
                endQuarterBPM: nil
            ),
            ScorePerformanceTempoEvent(
                sourceDirectionID: explicitID,
                performedOccurrenceIndex: 0,
                tick: 480,
                quarterBPM: 84,
                endTick: nil,
                endQuarterBPM: nil
            ),
        ]
    )

    let tempos = makeTimeline(plan: plan, activeRange: activeRange).events.filter {
        if case .tempo = $0.kind { true } else { false }
    }

    #expect(tempos.count == 1)
    #expect(tempos.first?.sourceEventID == explicitID.description)
    #expect(tempos.first?.kind == .tempo(quarterBPM: 84, endTick: nil, endQuarterBPM: nil))
}

@Test
func autoplayTimelineHoldsPlanPauseAtNoteOffBoundary() throws {
    let plan = makeTimelinePlan(
        notes: [TestScorePerformanceNote(midiNote: 60, velocity: 80, onTick: 0, offTick: 240)],
        annotations: [ScorePerformanceAnnotation(
            sourceDirectionID: directionID(ordinal: 5),
            performedOccurrenceIndex: 0,
            tick: 240,
            durationTicks: 120,
            kind: .pause,
            text: "fermata",
            provenance: []
        )]
    )
    let tempoMap = MusicXMLTempoMap(tempoEvents: [
        MusicXMLTempoEvent(
            tick: 0,
            quarterBPM: 120,
            scope: MusicXMLEventScope(partID: "P1", staff: nil, voice: nil)
        ),
    ])

    let timeline = AutoplayPerformanceTimeline.build(
        plan: plan,
        guideProjection: [],
        stepProjection: [],
        tempoMap: tempoMap,
        practiceHandMode: .both
    )
    let eventsAtRelease = timeline.events.filter { $0.tick == 240 }

    #expect(eventsAtRelease.count == 2)
    if case let .pauseSeconds(seconds) = eventsAtRelease[0].kind {
        #expect(abs(seconds - 0.125) < 0.000_001)
    } else {
        Issue.record("plan pause must precede final note-off")
    }
    #expect(eventsAtRelease[1].kind == .noteOff(midi: 60))
    #expect(eventsAtRelease[0].sourceEventID == directionID(ordinal: 5).description)
}

@Test
func autoplayPerformanceSnapshotPreservesSourceIdentityAndSortedPositions() {
    let timeline = AutoplayPerformanceTimeline(events: [
        .init(id: 0, sourceEventID: "note-1", tick: 0, kind: .noteOn(midi: 60, velocity: 72)),
        .init(id: 1, sourceEventID: "note-1", tick: 480, kind: .noteOff(midi: 60)),
    ])

    let snapshot = PerformanceEventSnapshot().encode(timeline)
    expectSnapshot(
        snapshot,
        equals: """
        position=0|eventID=0|sourceEventID=note-1|tick=0|kind=noteOn:60:72
        position=1|eventID=1|sourceEventID=note-1|tick=480|kind=noteOff:60
        """
    )
}

private func makeTimelinePlan(
    notes: [TestScorePerformanceNote],
    tempoEvents: [ScorePerformanceTempoEvent] = [],
    controllerEvents: [ScorePerformanceControllerEvent] = [],
    annotations: [ScorePerformanceAnnotation] = []
) -> ScorePerformancePlan {
    makeTestScorePerformancePlan(
        notes: notes,
        tempoEvents: tempoEvents,
        controllerEvents: controllerEvents,
        annotations: annotations
    )
}

private func makeTimeline(
    plan: ScorePerformancePlan,
    practiceHandMode: PracticeHandMode = .both,
    activeRange: PracticeActiveRange? = nil
) -> AutoplayPerformanceTimeline {
    AutoplayPerformanceTimeline.build(
        plan: plan,
        guideProjection: [],
        stepProjection: [],
        tempoMap: MusicXMLTempoMap(tempoEvents: []),
        practiceHandMode: practiceHandMode,
        activeRange: activeRange
    )
}

private func makeTimelineGuide(id: Int, tick: Int) -> PianoHighlightGuide {
    PianoHighlightGuide(
        id: id,
        kind: .trigger,
        tick: tick,
        durationTicks: nil,
        practiceStepIndex: id - 1,
        activeNotes: [],
        triggeredNotes: [],
        releasedMIDINotes: []
    )
}

private func directionID(ordinal: Int) -> MusicXMLDirectionSourceID {
    MusicXMLDirectionSourceID(
        partID: "P1",
        sourceMeasureIndex: 0,
        sourceMeasureNumberToken: "1",
        sourceOrdinal: ordinal
    )
}

private func timelineController(
    sourceID: MusicXMLDirectionSourceID,
    tick: Int,
    value: UInt8
) -> ScorePerformanceControllerEvent {
    ScorePerformanceControllerEvent(
        sourceDirectionID: sourceID,
        performedOccurrenceIndex: 0,
        tick: tick,
        controllerNumber: 64,
        value: value,
        outputCapabilityRequirement: .continuousControlChange
    )
}

private func timelineActiveRange(startTick: Int = 0, endTick: Int = 480) throws -> PracticeActiveRange {
    let span = MusicXMLMeasureSpan(
        partID: "P1",
        measureNumber: 1,
        sourceMeasureIndex: 0,
        sourceMeasureNumberToken: "1",
        occurrenceIndex: 0,
        startTick: startTick,
        endTick: endTick
    )
    let passage = try #require(PracticePassage(start: span.occurrenceID, end: span.occurrenceID))
    return PracticeActiveRange(
        passage: passage,
        occurrenceRange: 0 ..< 1,
        stepRange: 0 ..< 1,
        tickRange: startTick ..< endTick,
        measureSpans: [span]
    )
}
