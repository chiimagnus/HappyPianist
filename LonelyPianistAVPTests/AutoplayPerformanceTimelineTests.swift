@testable import LonelyPianistAVP
import Testing

@Test
func autoplayTimelineUsesGuidesForNoteOnOffAndGuideAdvance() {
    let guide = makeTimelineGuide(
        id: 1,
        tick: 120,
        notes: [
            makeTimelineNote(midi: 60, velocity: 80, onTick: 120, offTick: 360),
        ]
    )

    let timeline = AutoplayPerformanceTimeline.build(
        guides: [guide],
        steps: [PracticeStep(tick: 120, notes: [PracticeStepNote(midiNote: 60, staff: 1)])],
        pedalTimeline: MusicXMLPedalTimeline(events: []),
        fermataTimeline: MusicXMLFermataTimeline(fermataEvents: [], notes: []),
        tempoMap: MusicXMLTempoMap(tempoEvents: [])
    )

    #expect(timeline.events.map(\.tick) == [120, 120, 120, 360])
    #expect(timeline.events.contains { event in
        if case .noteOn(midi: 60, velocity: 80) = event.kind { return true }
        return false
    })
    #expect(timeline.events.contains { event in
        if case .noteOff(midi: 60) = event.kind { return true }
        return false
    })
    #expect(timeline.events.contains { event in
        if case .advanceGuide(index: 0, guideID: 1) = event.kind { return true }
        return false
    })
}

@Test
func autoplayTimelineDeduplicatesSameTickMIDINotesWithMaxVelocityAndOffTick() {
    let guide = makeTimelineGuide(
        id: 1,
        tick: 0,
        notes: [
            makeTimelineNote(midi: 60, velocity: 70, onTick: 0, offTick: 120),
            makeTimelineNote(midi: 60, velocity: 96, onTick: 0, offTick: 240),
        ]
    )

    let timeline = AutoplayPerformanceTimeline.build(
        guides: [guide],
        steps: [PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1)])],
        pedalTimeline: MusicXMLPedalTimeline(events: []),
        fermataTimeline: MusicXMLFermataTimeline(fermataEvents: [], notes: []),
        tempoMap: MusicXMLTempoMap(tempoEvents: [])
    )

    let noteOns = timeline.events.compactMap { event -> (Int, UInt8)? in
        if case let .noteOn(midi, velocity) = event.kind { return (midi, velocity) }
        return nil
    }
    let noteOffTicks = timeline.events.compactMap { event -> Int? in
        if case .noteOff(midi: 60) = event.kind { return event.tick }
        return nil
    }

    #expect(noteOns.count == 1)
    #expect(noteOns.first?.0 == 60)
    #expect(noteOns.first?.1 == 96)
    #expect(noteOffTicks == [240])
}

@Test
func autoplayTimelineRearticulatesOverlappingSameMIDINoteAtNextOnTick() {
    let first = makeTimelineGuide(
        id: 1,
        tick: 0,
        notes: [makeTimelineNote(midi: 60, velocity: 80, onTick: 0, offTick: 480)]
    )
    let second = makeTimelineGuide(
        id: 2,
        tick: 240,
        notes: [makeTimelineNote(midi: 60, velocity: 88, onTick: 240, offTick: 720)]
    )

    let timeline = AutoplayPerformanceTimeline.build(
        guides: [first, second],
        steps: [
            PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1)]),
            PracticeStep(tick: 240, notes: [PracticeStepNote(midiNote: 60, staff: 1)]),
        ],
        pedalTimeline: MusicXMLPedalTimeline(events: []),
        fermataTimeline: MusicXMLFermataTimeline(fermataEvents: [], notes: []),
        tempoMap: MusicXMLTempoMap(tempoEvents: [])
    )

    let midiEvents = timeline.events.compactMap { event -> String? in
        switch event.kind {
            case let .noteOn(midi, _): return "on:\(midi)@\(event.tick)"
            case let .noteOff(midi): return "off:\(midi)@\(event.tick)"
            default: return nil
        }
    }

    #expect(midiEvents == ["on:60@0", "off:60@240", "on:60@240", "off:60@720"])
}

@Test
func autoplayTimelineKeepsZeroDurationGuideNotesReleasable() {
    let guide = makeTimelineGuide(
        id: 1,
        tick: 0,
        notes: [makeTimelineNote(midi: 60, velocity: 80, onTick: 0, offTick: 0)]
    )

    let timeline = AutoplayPerformanceTimeline.build(
        guides: [guide],
        steps: [PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1)])],
        pedalTimeline: MusicXMLPedalTimeline(events: []),
        fermataTimeline: MusicXMLFermataTimeline(fermataEvents: [], notes: []),
        tempoMap: MusicXMLTempoMap(tempoEvents: [])
    )

    let midiEvents = timeline.events.compactMap { event -> String? in
        switch event.kind {
            case let .noteOn(midi, _): return "on:\(midi)@\(event.tick)"
            case let .noteOff(midi): return "off:\(midi)@\(event.tick)"
            default: return nil
        }
    }

    #expect(midiEvents == ["on:60@0", "off:60@1"])
}

@Test
func autoplayTimelineEmitsReleaseAndRedownForSameTickPedalChange() {
    let guide = makeTimelineGuide(
        id: 1,
        tick: 0,
        notes: [makeTimelineNote(midi: 60, velocity: 80, onTick: 0, offTick: 480)]
    )
    let pedalTimeline = MusicXMLPedalTimeline(
        events: [
            MusicXMLPedalEvent(
                partID: "P1",
                measureNumber: 1,
                tick: 0,
                kind: .start,
                isDown: true,
                timeOnlyPasses: nil
            ),
            MusicXMLPedalEvent(
                partID: "P1",
                measureNumber: 1,
                tick: 480,
                kind: .change,
                isDown: false,
                timeOnlyPasses: nil
            ),
            MusicXMLPedalEvent(
                partID: "P1",
                measureNumber: 1,
                tick: 480,
                kind: .change,
                isDown: true,
                timeOnlyPasses: nil
            ),
        ]
    )

    let timeline = AutoplayPerformanceTimeline.build(
        guides: [guide],
        steps: [PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1)])],
        pedalTimeline: pedalTimeline,
        fermataTimeline: MusicXMLFermataTimeline(fermataEvents: [], notes: []),
        tempoMap: MusicXMLTempoMap(tempoEvents: [])
    )

    let pedalEventsAtReleaseTick = timeline.events.compactMap { event -> String? in
        guard event.tick == 480 else { return nil }
        switch event.kind {
            case .pedalUp: return "up"
            case .pedalDown: return "down"
            default: return nil
        }
    }

    #expect(pedalEventsAtReleaseTick == ["up", "down"])
}

private func makeTimelineGuide(id: Int, tick: Int, notes: [PianoHighlightNote]) -> PianoHighlightGuide {
    PianoHighlightGuide(
        id: id,
        kind: .trigger,
        tick: tick,
        durationTicks: nil,
        practiceStepIndex: id - 1,
        activeNotes: notes,
        triggeredNotes: notes,
        releasedMIDINotes: []
    )
}

private func makeTimelineNote(midi: Int, velocity: UInt8, onTick: Int, offTick: Int) -> PianoHighlightNote {
    PianoHighlightNote(
        occurrenceID: "timeline-\(midi)-\(onTick)-\(offTick)-\(velocity)",
        midiNote: midi,
        staff: 1,
        voice: 1,
        velocity: velocity,
        onTick: onTick,
        offTick: offTick,
        fingeringText: nil
    )
}
