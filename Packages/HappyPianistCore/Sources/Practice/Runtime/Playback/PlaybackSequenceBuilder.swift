import Foundation
import MusicXML

public protocol PlaybackSequenceBuildingProtocol: Sendable {
    func buildPerformanceSequence(
        timeline: AutoplayPerformanceTimeline,
        tempoMap: MusicXMLTempoMap,
        startTick: Int,
        endTick: Int?,
        leadInSeconds: TimeInterval
    ) async throws -> PracticeSequencerSequence
}

public actor PlaybackSequenceBuilder: PlaybackSequenceBuildingProtocol {
    public init() {}

    public func buildPerformanceSequence(
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
