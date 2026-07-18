import Foundation

struct MusicXMLHandRouter {
    func routeIfNeeded(score: MusicXMLScore) -> MusicXMLScore {
        let hasAnyStaffTwoOrGreater = score.notes.contains { note in
            guard note.isRest == false else { return false }
            return (note.staff ?? 1) >= 2
        }
        guard hasAnyStaffTwoOrGreater == false else { return score }

        let pitchedNotes = score.notes.compactMap { note -> Int? in
            guard note.isRest == false else { return nil }
            return note.midiNote
        }
        guard pitchedNotes.isEmpty == false else { return score }

        let minNote = pitchedNotes.min() ?? 0
        let maxNote = pitchedNotes.max() ?? 0
        if maxNote - minNote < 12 {
            return score
        }

        let threshold = splitThresholdMIDINote(pitchedNotes: pitchedNotes)
        let routedNotes = score.notes.map { note in
            routeNote(note, threshold: threshold)
        }

        var copy = score
        copy.notes = routedNotes
        return copy
    }

    private func splitThresholdMIDINote(pitchedNotes: [Int]) -> Int {
        let sorted = pitchedNotes.sorted()
        let median = sorted[sorted.count / 2]
        if (50 ... 70).contains(median) {
            return median
        }
        return 60
    }

    private func routeNote(_ note: MusicXMLNoteEvent, threshold: Int) -> MusicXMLNoteEvent {
        guard note.isRest == false else { return note }
        guard let midiNote = note.midiNote else { return note }

        let existingStaff = note.staff ?? 1
        guard existingStaff <= 1 else { return note }

        let routedStaff = (midiNote < threshold) ? 2 : 1
        if note.staff == routedStaff {
            return note
        }

        return MusicXMLNoteEvent(
            sourceID: note.sourceID,
            partID: note.partID,
            measureNumber: note.measureNumber,
            tick: note.tick,
            durationTicks: note.durationTicks,
            midiNote: note.midiNote,
            isRest: note.isRest,
            isChord: note.isChord,
            isGrace: note.isGrace,
            graceSlash: note.graceSlash,
            graceStealTimePrevious: note.graceStealTimePrevious,
            graceStealTimeFollowing: note.graceStealTimeFollowing,
            tieStart: note.tieStart,
            tieStop: note.tieStop,
            staff: routedStaff,
            voice: note.voice,
            attackTicks: note.attackTicks,
            releaseTicks: note.releaseTicks,
            dynamicsOverrideVelocity: note.dynamicsOverrideVelocity,
            articulations: note.articulations,
            arpeggiate: note.arpeggiate,
            fingeringText: note.fingeringText,
            dotCount: note.dotCount
        )
    }
}
