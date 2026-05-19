import Foundation

actor PlaybackSequenceBuilder {
    func buildAutoplaySequence(
        timeline: AutoplayPerformanceTimeline,
        tempoMap: MusicXMLTempoMap,
        startTick: Int,
        initialSustainPedalDown: Bool,
        leadInSeconds: TimeInterval
    ) throws -> PracticeSequencerSequence {
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
    ) throws -> PracticeSequencerSequence {
        let builder = PracticeManualReplaySequenceBuilder(leadInSeconds: leadInSeconds)
        return try builder.buildSequence(steps: steps, tempoMap: tempoMap, stepRange: stepRange)
    }
}

