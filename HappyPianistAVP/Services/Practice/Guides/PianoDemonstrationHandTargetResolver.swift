import MusicXML
import Practice

struct PianoDemonstrationHandTargetResolver {
    func resolve(
        highlightGuide: PianoHighlightGuide?,
        keyboardGeometry: PianoKeyboardGeometry?,
        fingeringPlan: PianoFingeringPlanner.Plan? = nil
    ) -> PianoDemonstrationHandCoverage {
        guard let highlightGuide else {
            return PianoDemonstrationHandCoverage()
        }
        guard let keyboardGeometry else {
            return PianoDemonstrationHandCoverage(
                guideID: highlightGuide.id,
                uncoveredKeys: currentNotes(in: highlightGuide).map {
                    uncoveredKey(for: $0.note, reason: .missingGeometry)
                },
                releasedMIDINotes: highlightGuide.releasedMIDINotes
            )
        }
        guard let fingeringPlan else {
            return PianoDemonstrationHandCoverage(
                guideID: highlightGuide.id,
                uncoveredKeys: currentNotes(in: highlightGuide).map {
                    uncoveredKey(for: $0.note, reason: .fingeringUnplanned)
                },
                releasedMIDINotes: highlightGuide.releasedMIDINotes
            )
        }

        var targets: [PianoDemonstrationHandTarget] = []
        var uncoveredKeys: [PianoDemonstrationHandCoverage.UncoveredKey] = []
        for item in currentNotes(in: highlightGuide) {
            guard let result = fingeringPlan.result(forOccurrenceID: item.note.occurrenceID),
                  case let .planned(scoreHand, fingerValue, _) = result.resolution,
                  let hand = PianoDemonstrationHand(scoreHand: scoreHand),
                  let finger = PianoDemonstrationFinger(rawValue: fingerValue)
            else {
                uncoveredKeys.append(uncoveredKey(for: item.note, reason: .fingeringUnplanned))
                continue
            }
            guard let key = keyboardGeometry.key(for: item.note.midiNote) else {
                uncoveredKeys.append(uncoveredKey(for: item.note, reason: .missingGeometry))
                continue
            }
            targets.append(PianoDemonstrationHandTarget(
                occurrenceID: item.note.occurrenceID,
                hand: hand,
                finger: finger,
                midiNote: item.note.midiNote,
                phase: item.phase,
                contactPositionLocal: SIMD3<Float>(
                    key.localCenter.x,
                    key.surfaceLocalY,
                    key.localCenter.z
                ),
                velocity: item.note.velocity
            ))
        }

        return PianoDemonstrationHandCoverage(
            guideID: highlightGuide.id,
            coveredTargets: targets.sorted {
                if $0.hand != $1.hand { return $0.hand == .left }
                if $0.midiNote != $1.midiNote { return $0.midiNote < $1.midiNote }
                return $0.occurrenceID < $1.occurrenceID
            },
            uncoveredKeys: uncoveredKeys.sorted {
                if $0.midiNote != $1.midiNote { return $0.midiNote < $1.midiNote }
                return $0.occurrenceID < $1.occurrenceID
            },
            releasedMIDINotes: highlightGuide.releasedMIDINotes
        )
    }

    private func currentNotes(in highlightGuide: PianoHighlightGuide) -> [NoteState] {
        var noteByOccurrenceID: [String: NoteState] = [:]
        for note in highlightGuide.activeNotes {
            noteByOccurrenceID[note.occurrenceID] = NoteState(note: note, phase: .held)
        }
        for note in highlightGuide.triggeredNotes {
            noteByOccurrenceID[note.occurrenceID] = NoteState(note: note, phase: .triggered)
        }
        return noteByOccurrenceID.values.sorted {
            if $0.note.midiNote != $1.note.midiNote { return $0.note.midiNote < $1.note.midiNote }
            return $0.note.occurrenceID < $1.note.occurrenceID
        }
    }

    private func uncoveredKey(
        for note: PianoHighlightNote,
        reason: PianoDemonstrationHandCoverage.Reason
    ) -> PianoDemonstrationHandCoverage.UncoveredKey {
        PianoDemonstrationHandCoverage.UncoveredKey(
            midiNote: note.midiNote,
            occurrenceID: note.occurrenceID,
            reason: reason
        )
    }
}

private extension PianoDemonstrationHand {
    init?(scoreHand: ScoreHand) {
        switch scoreHand {
        case .left: self = .left
        case .right: self = .right
        case .unknown: return nil
        }
    }
}

private struct NoteState {
    let note: PianoHighlightNote
    let phase: PianoDemonstrationTouchPhase
}
