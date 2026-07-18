import Foundation

protocol PracticeStepBuilderProtocol {
    func buildSteps(
        from score: MusicXMLScore,
        expressivity: MusicXMLExpressivityOptions,
        handAssignments: [MusicXMLSourceNoteID: ScoreHandAssignment]
    ) -> PracticeStepBuildResult
}

extension PracticeStepBuilderProtocol {
    func buildSteps(from score: MusicXMLScore) -> PracticeStepBuildResult {
        buildSteps(
            from: score,
            expressivity: MusicXMLExpressivityOptions(),
            handAssignments: [:]
        )
    }

    func buildSteps(
        from score: MusicXMLScore,
        expressivity: MusicXMLExpressivityOptions
    ) -> PracticeStepBuildResult {
        buildSteps(from: score, expressivity: expressivity, handAssignments: [:])
    }
}

struct PracticeStepBuilder: PracticeStepBuilderProtocol {
    private struct StepNoteKey: Hashable {
        let midiNote: Int
        let staff: Int
        let voice: Int
    }

    private let playableRange = 21 ... 108

    func buildSteps(
        from score: MusicXMLScore,
        expressivity: MusicXMLExpressivityOptions,
        handAssignments: [MusicXMLSourceNoteID: ScoreHandAssignment]
    ) -> PracticeStepBuildResult {
        var grouped: [Int: [StepNoteKey: (
            handAssignment: ScoreHandAssignment,
            velocity: UInt8,
            onTickOffset: Int,
            fingeringText: String?
        )]] =
            [:]
        var unsupportedNoteCount = 0
        let timingSchedule = ScoreTimingScheduleBuilder().build(
            notes: score.notes,
            graceEnabled: expressivity.graceEnabled,
            logicalInstruments: score.logicalInstruments,
            arpeggiateEnabled: expressivity.arpeggiateEnabled
        )
        let velocityResolver = MusicXMLVelocityResolver(
            dynamicEvents: score.dynamicEvents,
            wedgeEvents: score.wedgeEvents,
            wedgeEnabled: expressivity.wedgeEnabled
        )
        for (index, noteEvent) in score.notes.enumerated() {
            if noteEvent.isRest { continue }
            if noteEvent.isGrace, expressivity.graceEnabled == false { continue }
            if noteEvent.tieStop { continue }
            guard let midiNote = noteEvent.midiNote else { continue }
            guard playableRange.contains(midiNote) else {
                unsupportedNoteCount += 1
                continue
            }

            let velocity = velocityResolver.velocity(for: noteEvent)
            let performedOnTick = timingSchedule[index].performedOnTick
            let effectiveTick = noteEvent.isGrace ? performedOnTick : noteEvent.tick
            let onTickOffset = performedOnTick - effectiveTick
            let staff = noteEvent.staff ?? 1
            let voice = noteEvent.voice ?? 1
            let key = StepNoteKey(midiNote: midiNote, staff: staff, voice: voice)
            var map = grouped[effectiveTick] ?? [:]
            if map[key] == nil {
                map[key] = (
                    handAssignment: noteEvent.sourceID.flatMap { handAssignments[$0] } ?? .unknown,
                    velocity: velocity,
                    onTickOffset: onTickOffset,
                    fingeringText: noteEvent.fingeringText
                )
            }
            grouped[effectiveTick] = map
        }

        let steps = grouped.keys.sorted().map { tick in
            let notesMap = grouped[tick] ?? [:]
            let notes = notesMap.keys.sorted { lhs, rhs in
                if lhs.midiNote != rhs.midiNote { return lhs.midiNote < rhs.midiNote }
                if lhs.staff != rhs.staff { return lhs.staff < rhs.staff }
                return lhs.voice < rhs.voice
            }.map { key in
                let entry = notesMap[key]
                return PracticeStepNote(
                    midiNote: key.midiNote,
                    staff: key.staff,
                    voice: key.voice,
                    velocity: entry?.velocity ?? 96,
                    onTickOffset: entry?.onTickOffset ?? 0,
                    fingeringText: entry?.fingeringText,
                    handAssignment: entry?.handAssignment ?? .unknown
                )
            }
            return PracticeStep(tick: tick, notes: notes)
        }

        return PracticeStepBuildResult(steps: steps, unsupportedNoteCount: unsupportedNoteCount)
    }

}
