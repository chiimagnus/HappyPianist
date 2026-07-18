import Foundation

struct ScoreTimingScheduleBuilder {
    func build(
        notes: [MusicXMLNoteEvent],
        performanceTimingEnabled: Bool = false
    ) -> ScoreTimingSchedule {
        ScoreTimingSchedule(entries: notes.enumerated().map { index, note in
            let writtenOnTick = max(0, note.tick)
            let writtenOffTick = max(writtenOnTick, writtenOnTick + max(0, note.durationTicks))
            let onsetOffsetTicks = performanceTimingEnabled ? (note.attackTicks ?? 0) : 0
            let releaseOffsetTicks = performanceTimingEnabled ? (note.releaseTicks ?? 0) : 0
            let performedOnTick = max(0, writtenOnTick + onsetOffsetTicks)
            let performedOffTick = max(
                performedOnTick,
                writtenOffTick + releaseOffsetTicks
            )
            let usesPerformanceOffsets = onsetOffsetTicks != 0 || releaseOffsetTicks != 0
            return ScoreTimingEntry(
                noteIndex: index,
                sourceNoteID: note.sourceID,
                performedNoteID: note.performedID,
                writtenOnTick: writtenOnTick,
                writtenOffTick: writtenOffTick,
                performedOnTick: performedOnTick,
                performedOffTick: performedOffTick,
                onsetOffsetTicks: onsetOffsetTicks,
                releaseOffsetTicks: releaseOffsetTicks,
                releasePolicy: usesPerformanceOffsets ? .performanceOffsets : .writtenDuration,
                provenance: usesPerformanceOffsets ? [.score, .performanceOffset] : [.score]
            )
        })
    }
}
