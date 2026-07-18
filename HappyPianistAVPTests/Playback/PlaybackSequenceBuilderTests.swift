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
