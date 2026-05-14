import Foundation

/// Normalizes a common (but non-standard-for-piano) MusicXML export pattern:
/// two separate `<part>` entries (one treble clef, one bass clef) representing a single piano grand staff.
///
/// Our practice pipeline later filters down to a single `partID`. If left unmodified, the bass `<part>`
/// gets dropped entirely, resulting in missing left-hand notes.
struct MusicXMLPianoGrandStaffNormalizer {
    func normalize(score: MusicXMLScore) -> MusicXMLScore {
        let notePartIDs = Set(score.notes.map(\.partID))
        guard notePartIDs.count == 2 else { return score }

        // If the source already encodes multi-staff notes (staff >= 2), we don't need to normalize.
        if score.notes.contains(where: { ($0.staff ?? 1) >= 2 }) {
            return score
        }

        guard let mapping = inferTrebleAndBassPartIDs(score: score) else { return score }
        let (treblePartID, bassPartID) = mapping

        guard notePartIDs.contains(treblePartID), notePartIDs.contains(bassPartID) else { return score }

        let mergedNotes = score.notes.map { note in
            guard note.partID == bassPartID else { return note }
            return MusicXMLNoteEvent(
                partID: treblePartID,
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
                staff: note.staff,
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

        var copy = score
        copy.notes = mergedNotes
        return copy
    }

    private func inferTrebleAndBassPartIDs(score: MusicXMLScore) -> (treble: String, bass: String)? {
        // We infer by the first clef sign seen per part: "G" => treble, "F" => bass.
        // This matches exports like music21 that emit two piano parts with separate clefs.
        var earliestClefByPart: [String: (tick: Int, sign: String)] = [:]

        for event in score.clefEvents {
            let partID = event.scope.partID
            guard let token = event.signToken?.trimmingCharacters(in: .whitespacesAndNewlines),
                  token.isEmpty == false
            else { continue }
            let sign = token.uppercased()
            guard sign == "G" || sign == "F" else { continue }

            if let existing = earliestClefByPart[partID] {
                if event.tick < existing.tick {
                    earliestClefByPart[partID] = (tick: event.tick, sign: sign)
                }
            } else {
                earliestClefByPart[partID] = (tick: event.tick, sign: sign)
            }
        }

        guard earliestClefByPart.count >= 2 else { return nil }

        let treblePartID = earliestClefByPart.first(where: { $0.value.sign == "G" })?.key
        let bassPartID = earliestClefByPart.first(where: { $0.value.sign == "F" })?.key
        guard let treblePartID, let bassPartID, treblePartID != bassPartID else { return nil }
        return (treble: treblePartID, bass: bassPartID)
    }
}

