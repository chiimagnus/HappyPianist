import Foundation

protocol PlaybackSequenceBuildingProtocol: Sendable {
    func buildPerformanceSequence(
        timeline: AutoplayPerformanceTimeline,
        tempoMap: MusicXMLTempoMap,
        startTick: Int,
        endTick: Int?,
        leadInSeconds: TimeInterval
    ) async throws -> PracticeSequencerSequence
}

actor PlaybackSequenceBuilder: PlaybackSequenceBuildingProtocol {
    func buildPerformanceSequence(
        timeline: AutoplayPerformanceTimeline,
        tempoMap: MusicXMLTempoMap,
        startTick: Int,
        endTick: Int?,
        leadInSeconds: TimeInterval
    ) async throws -> PracticeSequencerSequence {
        let builder = PracticeSequencerSequenceBuilder()
        let schedule = builder.buildPerformanceEventSchedule(
            timeline: timeline,
            tempoMap: tempoMap,
            startTick: startTick,
            leadInSeconds: leadInSeconds,
            endTick: endTick
        )
        return try builder.buildSequence(from: schedule)
    }
}
