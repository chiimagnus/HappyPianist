import Foundation

protocol PlaybackSequenceBuildingProtocol: Sendable {
    func buildAutoplaySequence(
        timeline: AutoplayPerformanceTimeline,
        tempoMap: MusicXMLTempoMap,
        startTick: Int,
        initialSustainPedalDown: Bool,
        leadInSeconds: TimeInterval
    ) async throws -> PracticeSequencerSequence

    func buildManualReplaySequence(
        steps: [PracticeStep],
        tempoMap: MusicXMLTempoMap,
        stepRange: Range<Int>,
        leadInSeconds: TimeInterval
    ) async throws -> PracticeSequencerSequence
}

actor PlaybackSequenceBuilder: PlaybackSequenceBuildingProtocol {
    func buildAutoplaySequence(
        timeline: AutoplayPerformanceTimeline,
        tempoMap: MusicXMLTempoMap,
        startTick: Int,
        initialSustainPedalDown: Bool,
        leadInSeconds: TimeInterval
    ) async throws -> PracticeSequencerSequence {
        let builder = PracticeSequencerSequenceBuilder()
        let schedule = builder.buildAudioEventSchedule(
            timeline: timeline,
            tempoMap: tempoMap,
            startTick: startTick,
            initialSustainPedalDown: initialSustainPedalDown,
            leadInSeconds: leadInSeconds
        )
        return try builder.buildSequence(from: schedule)
    }

    func buildManualReplaySequence(
        steps: [PracticeStep],
        tempoMap: MusicXMLTempoMap,
        stepRange: Range<Int>,
        leadInSeconds: TimeInterval
    ) async throws -> PracticeSequencerSequence {
        let builder = PracticeManualReplaySequenceBuilder(leadInSeconds: leadInSeconds)
        return try builder.buildSequence(steps: steps, tempoMap: tempoMap, stepRange: stepRange)
    }
}

