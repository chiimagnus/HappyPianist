@testable import LonelyPianistAVP
import Foundation
import Testing

private let defaultTempoScope = MusicXMLEventScope(partID: "P1", staff: nil, voice: nil)

@Test
func sequenceBuilderAppliesPauseBeforeSameTickAudioEvents() async throws {
    let tempoMap = MusicXMLTempoMap(
        tempoEvents: [MusicXMLTempoEvent(tick: 0, quarterBPM: 120, scope: defaultTempoScope)]
    )
    let timeline = AutoplayPerformanceTimeline(
        events: [
            AutoplayPerformanceTimeline.Event(id: 0, tick: 0, kind: .noteOn(midi: 60, velocity: 96)),
            AutoplayPerformanceTimeline.Event(id: 1, tick: 480, kind: .pauseSeconds(1.0)),
            AutoplayPerformanceTimeline.Event(id: 2, tick: 480, kind: .noteOff(midi: 60)),
            AutoplayPerformanceTimeline.Event(id: 3, tick: 480, kind: .pedalUp),
            AutoplayPerformanceTimeline.Event(id: 4, tick: 480, kind: .pedalDown),
            AutoplayPerformanceTimeline.Event(id: 5, tick: 480, kind: .noteOn(midi: 62, velocity: 96)),
            AutoplayPerformanceTimeline.Event(id: 6, tick: 960, kind: .noteOff(midi: 62)),
        ]
    )

    let builder = PracticeSequencerSequenceBuilder(midiChannel: 0)
    let schedule = builder.buildAudioEventSchedule(timeline: timeline, tempoMap: tempoMap, startTick: 0)

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
func sequenceBuilderExportsMIDISMFData() async throws {
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
    let schedule = builder.buildAudioEventSchedule(timeline: timeline, tempoMap: tempoMap, startTick: 0)
    let sequence = try builder.buildSequence(from: schedule)

    #expect(sequence.midiData.isEmpty == false)
    #expect(sequence.durationSeconds > 0)
}

@Test
func sequenceBuilderInjectsInitialSustainPedalStateWhenStartingMidSong() async {
    let tempoMap = MusicXMLTempoMap(
        tempoEvents: [MusicXMLTempoEvent(tick: 0, quarterBPM: 120, scope: defaultTempoScope)]
    )
    let timeline = AutoplayPerformanceTimeline(
        events: [
            AutoplayPerformanceTimeline.Event(id: 0, tick: 0, kind: .pedalDown),
            AutoplayPerformanceTimeline.Event(id: 1, tick: 480, kind: .noteOn(midi: 60, velocity: 96)),
            AutoplayPerformanceTimeline.Event(id: 2, tick: 960, kind: .noteOff(midi: 60)),
        ]
    )

    let builder = PracticeSequencerSequenceBuilder(midiChannel: 0)
    let schedule = builder.buildAudioEventSchedule(
        timeline: timeline,
        tempoMap: tempoMap,
        startTick: 480,
        initialSustainPedalDown: true
    )

    #expect(schedule.first?.kind == .controlChange(controller: 64, value: 127))
    #expect(abs((schedule.first?.timeSeconds ?? -1) - 0.0) < 1e-9)
}
