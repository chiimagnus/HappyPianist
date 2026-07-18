import Foundation
@testable import HappyPianistAVP
import Testing

private let defaultTempoScope = MusicXMLEventScope(partID: "P1", staff: nil, voice: nil)

@Test
func sequenceBuilderAppliesPauseBeforeSameTickAudioEvents() {
    let tempoMap = MusicXMLTempoMap(
        tempoEvents: [MusicXMLTempoEvent(tick: 0, quarterBPM: 120, scope: defaultTempoScope)]
    )
    let timeline = AutoplayPerformanceTimeline(
        events: [
            AutoplayPerformanceTimeline.Event(id: 0, tick: 0, kind: .noteOn(midi: 60, velocity: 96)),
            AutoplayPerformanceTimeline.Event(id: 1, tick: 480, kind: .pauseSeconds(1.0)),
            AutoplayPerformanceTimeline.Event(id: 2, tick: 480, kind: .noteOff(midi: 60)),
            AutoplayPerformanceTimeline.Event(id: 3, tick: 480, kind: .controlChange(controller: 64, value: 0)),
            AutoplayPerformanceTimeline.Event(id: 4, tick: 480, kind: .controlChange(controller: 64, value: 127)),
            AutoplayPerformanceTimeline.Event(id: 5, tick: 480, kind: .noteOn(midi: 62, velocity: 96)),
            AutoplayPerformanceTimeline.Event(id: 6, tick: 960, kind: .noteOff(midi: 62)),
        ]
    )

    let builder = PracticeSequencerSequenceBuilder(midiChannel: 0)
    let schedule = builder.buildPerformanceEventSchedule(timeline: timeline, tempoMap: tempoMap, startTick: 0)

    #expect(schedule.map(\.kind) == [
        .noteOn(midi: 60, velocity: 96),
        .noteOff(midi: 60),
        .controlChange(controller: 64, value: 0),
        .controlChange(controller: 64, value: 127),
        .noteOn(midi: 62, velocity: 96),
        .noteOff(midi: 62),
    ])

    #expect(abs(schedule[0].timeSeconds - 0.0) < 1e-9)

    #expect(abs(schedule[1].timeSeconds - 1.5) < 1e-9)
    #expect(abs(schedule[2].timeSeconds - 1.5) < 1e-9)
    #expect(abs(schedule[3].timeSeconds - 1.5) < 1e-9)
    #expect(abs(schedule[4].timeSeconds - 1.5) < 1e-9)

    #expect(abs(schedule[5].timeSeconds - 2.0) < 1e-9)
}

@Test
func sequenceBuilderExportsMIDISMFData() throws {
    let tempoMap = MusicXMLTempoMap(
        tempoEvents: [MusicXMLTempoEvent(tick: 0, quarterBPM: 120, scope: defaultTempoScope)]
    )
    let timeline = AutoplayPerformanceTimeline(
        events: [
            AutoplayPerformanceTimeline.Event(id: 0, tick: 0, kind: .noteOn(midi: 60, velocity: 96)),
            AutoplayPerformanceTimeline.Event(id: 1, tick: 480, kind: .noteOff(midi: 60)),
        ]
    )

    let builder = PracticeSequencerSequenceBuilder(midiChannel: 0)
    let schedule = builder.buildPerformanceEventSchedule(timeline: timeline, tempoMap: tempoMap, startTick: 0)
    let sequence = try builder.buildSequence(from: schedule)

    #expect(sequence.midiData.isEmpty == false)
    #expect(sequence.durationSeconds > 0)
}

@Test
func sequenceBuilderRestoresPlanControllerContextWhenStartingMidSong() {
    let tempoMap = MusicXMLTempoMap(
        tempoEvents: [MusicXMLTempoEvent(tick: 0, quarterBPM: 120, scope: defaultTempoScope)]
    )
    let timeline = AutoplayPerformanceTimeline(
        events: [
            AutoplayPerformanceTimeline.Event(
                id: 0,
                sourceEventID: "controller-volume",
                tick: 0,
                kind: .controlChange(controller: 7, value: 100)
            ),
            AutoplayPerformanceTimeline.Event(
                id: 1,
                sourceEventID: "controller-sustain",
                tick: 0,
                kind: .controlChange(controller: 64, value: 127)
            ),
            AutoplayPerformanceTimeline.Event(
                id: 2,
                sourceEventID: "note-1",
                tick: 480,
                kind: .noteOn(midi: 60, velocity: 96)
            ),
            AutoplayPerformanceTimeline.Event(
                id: 3,
                sourceEventID: "note-1",
                tick: 960,
                kind: .noteOff(midi: 60)
            ),
        ]
    )

    let builder = PracticeSequencerSequenceBuilder(midiChannel: 0)
    let schedule = builder.buildPerformanceEventSchedule(
        timeline: timeline,
        tempoMap: tempoMap,
        startTick: 480
    )

    #expect(schedule.prefix(2).map(\.kind) == [
        .controlChange(controller: 7, value: 100),
        .controlChange(controller: 64, value: 127),
    ])
    #expect(schedule.prefix(2).map(\.sourceEventID) == ["controller-volume", "controller-sustain"])
    #expect(abs((schedule.first?.timeSeconds ?? -1) - 0.0) < 1e-9)
}

@Test
func sequenceBuilderDoesNotDuplicateControllerContextAlreadyProjectedAtStartTick() {
    let tempoMap = MusicXMLTempoMap(
        tempoEvents: [MusicXMLTempoEvent(tick: 0, quarterBPM: 120, scope: defaultTempoScope)]
    )
    let timeline = AutoplayPerformanceTimeline(events: [
        .init(id: 0, tick: 480, kind: .controlChange(controller: 64, value: 127)),
        .init(id: 1, tick: 480, kind: .noteOn(midi: 60, velocity: 96)),
    ])

    let schedule = PracticeSequencerSequenceBuilder().buildPerformanceEventSchedule(
        timeline: timeline,
        tempoMap: tempoMap,
        startTick: 480
    )

    #expect(schedule.filter { $0.kind == .controlChange(controller: 64, value: 127) }.count == 1)
}

@Test
func sequenceBuilderKeepsPlanPauseBeforeClosingReplayBoundary() {
    let tempoMap = MusicXMLTempoMap(
        tempoEvents: [MusicXMLTempoEvent(tick: 0, quarterBPM: 120, scope: defaultTempoScope)]
    )
    let timeline = AutoplayPerformanceTimeline(events: [
        .init(id: 0, sourceEventID: "note-1", tick: 0, kind: .noteOn(midi: 60, velocity: 96)),
        .init(id: 1, sourceEventID: "pause-1", tick: 240, kind: .pauseSeconds(1)),
        .init(id: 2, sourceEventID: "note-1", tick: 480, kind: .noteOff(midi: 60)),
    ])

    let schedule = PracticeSequencerSequenceBuilder().buildPerformanceEventSchedule(
        timeline: timeline,
        tempoMap: tempoMap,
        startTick: 0,
        endTick: 240
    )

    #expect(schedule.map(\.kind) == [
        .noteOn(midi: 60, velocity: 96),
        .noteOff(midi: 60),
    ])
    #expect(abs(schedule[1].timeSeconds - 1.25) < 1e-9)
    #expect(schedule[1].sourceEventID == "note-1")
}

@Test
func sequencerPerformanceSnapshotPreservesControllerAndTime() {
    let events = [
        PracticeSequencerMIDIEvent(
            sourceEventID: "controller-1",
            timeSeconds: 0,
            kind: .controlChange(controller: 64, value: 127)
        ),
        PracticeSequencerMIDIEvent(
            sourceEventID: "note-1",
            timeSeconds: 0.5,
            kind: .noteOn(midi: 60, velocity: 80)
        ),
    ]

    let snapshot = PerformanceEventSnapshot().encode(events)
    #expect(snapshot.contains("position=0|sourceEventID=controller-1|seconds=0|kind=cc:64:127"))
    #expect(snapshot.contains("position=1|sourceEventID=note-1|seconds=0.5|kind=noteOn:60:80"))
}
