import Foundation

nonisolated struct PracticeManualReplaySequenceBuilder {
    private let chordDurationSeconds: TimeInterval
    private let velocity: UInt8
    private let leadInSeconds: TimeInterval

    init(chordDurationSeconds: TimeInterval = 0.35, velocity: UInt8 = 96, leadInSeconds: TimeInterval = 0) {
        self.chordDurationSeconds = chordDurationSeconds
        self.velocity = velocity
        self.leadInSeconds = leadInSeconds
    }

    func buildSequence(
        steps: [PracticeStep],
        tempoMap: MusicXMLTempoMap,
        stepRange: Range<Int>
    ) throws -> PracticeSequencerSequence {
        let schedule = buildSchedule(steps: steps, tempoMap: tempoMap, stepRange: stepRange)
        return try PracticeSequencerSequenceBuilder().buildSequence(from: schedule)
    }

    func buildSchedule(
        steps: [PracticeStep],
        tempoMap: MusicXMLTempoMap,
        stepRange: Range<Int>
    ) -> [PracticeSequencerMIDIEvent] {
        guard stepRange.isEmpty == false else { return [] }
        guard steps.indices.contains(stepRange.lowerBound) else { return [] }

        let baseTick = steps[stepRange.lowerBound].tick
        let baseSeconds = tempoMap.timeSeconds(atTick: baseTick)

        var schedule: [PracticeSequencerMIDIEvent] = []
        schedule.reserveCapacity(stepRange.count * 10)

        for index in stepRange {
            guard steps.indices.contains(index) else { break }
            let step = steps[index]
            let stepSeconds = tempoMap.timeSeconds(atTick: step.tick) - baseSeconds + leadInSeconds

            schedule.append(
                PracticeSequencerMIDIEvent(
                    timeSeconds: stepSeconds,
                    kind: .controlChange(controller: 123, value: 0)
                )
            )

            let uniqueMIDINotes = Set(step.notes.map(\.midiNote)).sorted()
            for midi in uniqueMIDINotes {
                schedule.append(
                    PracticeSequencerMIDIEvent(
                        timeSeconds: stepSeconds,
                        kind: .noteOn(midi: midi, velocity: velocity)
                    )
                )
                schedule.append(
                    PracticeSequencerMIDIEvent(
                        timeSeconds: stepSeconds + chordDurationSeconds,
                        kind: .noteOff(midi: midi)
                    )
                )
            }
        }

        return schedule
    }
}
