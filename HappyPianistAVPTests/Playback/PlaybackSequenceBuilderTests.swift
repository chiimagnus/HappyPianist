import Foundation
@testable import HappyPianistAVP
import Testing

private let defaultTempoScope = MusicXMLEventScope(partID: "P1", staff: nil, voice: nil)

@Test
func playbackSequenceBuilderBuildsPlanDerivedPerformanceSequence() async throws {
    let builder = PlaybackSequenceBuilder()
    let tempoMap = MusicXMLTempoMap(
        tempoEvents: [MusicXMLTempoEvent(tick: 0, quarterBPM: 120, scope: defaultTempoScope)]
    )
    let timeline = AutoplayPerformanceTimeline(
        events: [
            AutoplayPerformanceTimeline.Event(
                id: 0,
                sourceEventID: "note-1",
                tick: 0,
                kind: .noteOn(midi: 60, velocity: 96)
            ),
            AutoplayPerformanceTimeline.Event(
                id: 1,
                sourceEventID: "note-1",
                tick: 480,
                kind: .noteOff(midi: 60)
            ),
        ]
    )

    let sequence = try await builder.buildPerformanceSequence(
        timeline: timeline,
        tempoMap: tempoMap,
        startTick: 0,
        endTick: nil,
        leadInSeconds: 0.05
    )

    #expect(sequence.midiData.isEmpty == false)
    #expect(sequence.durationSeconds > 0)
    #expect(sequence.events.map(\.sourceEventID) == ["note-1", "note-1"])
}

@Test
func playbackSequenceBuilderClosesPlanNotesAtReplayBoundary() async throws {
    let builder = PlaybackSequenceBuilder()
    let tempoMap = MusicXMLTempoMap(
        tempoEvents: [MusicXMLTempoEvent(tick: 0, quarterBPM: 120, scope: defaultTempoScope)]
    )
    let timeline = AutoplayPerformanceTimeline(events: [
        .init(id: 0, sourceEventID: "note-1", tick: 0, kind: .noteOn(midi: 60, velocity: 96)),
        .init(id: 1, sourceEventID: "note-1", tick: 480, kind: .noteOff(midi: 60)),
        .init(id: 2, sourceEventID: "note-2", tick: 480, kind: .noteOn(midi: 62, velocity: 80)),
    ])

    let sequence = try await builder.buildPerformanceSequence(
        timeline: timeline,
        tempoMap: tempoMap,
        startTick: 0,
        endTick: 240,
        leadInSeconds: 0.05
    )

    #expect(sequence.events.map(\.kind) == [
        .noteOn(midi: 60, velocity: 96),
        .noteOff(midi: 60),
    ])
    #expect(sequence.events.map(\.sourceEventID) == ["note-1", "note-1"])
}

@Test
func playbackSequenceBuilderPreservesPolyphonicIdentityAtReplayBoundary() async throws {
    let timeline = AutoplayPerformanceTimeline(events: [
        .init(id: 0, sourceEventID: "voice-1", tick: 0, kind: .noteOn(midi: 60, velocity: 72)),
        .init(id: 1, sourceEventID: "voice-2", tick: 0, kind: .noteOn(midi: 60, velocity: 88)),
        .init(id: 2, sourceEventID: "voice-1", tick: 480, kind: .noteOff(midi: 60)),
        .init(id: 3, sourceEventID: "voice-2", tick: 480, kind: .noteOff(midi: 60)),
    ])

    let sequence = try await PlaybackSequenceBuilder().buildPerformanceSequence(
        timeline: timeline,
        tempoMap: MusicXMLTempoMap(
            tempoEvents: [MusicXMLTempoEvent(tick: 0, quarterBPM: 120, scope: defaultTempoScope)]
        ),
        startTick: 0,
        endTick: 240,
        leadInSeconds: 0
    )

    #expect(sequence.events.map(\.sourceEventID) == ["voice-1", "voice-2", "voice-1", "voice-2"])
    #expect(sequence.events.map(\.kind) == [
        .noteOn(midi: 60, velocity: 72),
        .noteOn(midi: 60, velocity: 88),
        .noteOff(midi: 60),
        .noteOff(midi: 60),
    ])
}
