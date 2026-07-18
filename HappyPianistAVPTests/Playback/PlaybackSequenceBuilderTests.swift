import Foundation
@testable import HappyPianistAVP
import Testing

private let defaultTempoScope = MusicXMLEventScope(partID: "P1", staff: nil, voice: nil)

@Test
func playbackSequenceBuilderBuildsAutoplaySequence() async throws {
    let builder = PlaybackSequenceBuilder()
    let tempoMap = MusicXMLTempoMap(
        tempoEvents: [MusicXMLTempoEvent(tick: 0, quarterBPM: 120, scope: defaultTempoScope)]
    )
    let timeline = AutoplayPerformanceTimeline(
        events: [
            AutoplayPerformanceTimeline.Event(id: 0, tick: 0, kind: .noteOn(midi: 60, velocity: 96)),
            AutoplayPerformanceTimeline.Event(id: 1, tick: 480, kind: .noteOff(midi: 60)),
        ]
    )

    let sequence = try await builder.buildAutoplaySequence(
        timeline: timeline,
        tempoMap: tempoMap,
        startTick: 0,
        initialSustainPedalDown: false,
        leadInSeconds: 0.05
    )

    #expect(sequence.midiData.isEmpty == false)
    #expect(sequence.durationSeconds > 0)
}

@Test
func playbackSequenceBuilderBuildsManualReplaySequence() async throws {
    let builder = PlaybackSequenceBuilder()
    let tempoMap = MusicXMLTempoMap(
        tempoEvents: [MusicXMLTempoEvent(tick: 0, quarterBPM: 120, scope: defaultTempoScope)]
    )
    let steps: [PracticeStep] = [
        PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1, handAssignment: .unknown)]),
        PracticeStep(tick: 120, notes: [PracticeStepNote(midiNote: 62, staff: 1, handAssignment: .unknown)]),
    ]

    let sequence = try await builder.buildManualReplaySequence(
        steps: steps,
        tempoMap: tempoMap,
        stepRange: 0 ..< 2,
        leadInSeconds: 0.05
    )

    #expect(sequence.midiData.isEmpty == false)
    #expect(sequence.durationSeconds > 0)
}
