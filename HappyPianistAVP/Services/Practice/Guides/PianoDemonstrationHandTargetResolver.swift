import MusicXML
import Practice

struct PianoDemonstrationHandTargetResolver {
    private static let maximumHandSpanMeters: Float = 0.20

    func resolve(
        highlightGuide: PianoHighlightGuide?,
        keyboardGeometry: PianoKeyboardGeometry?
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

        let candidateResolution = currentCandidates(
            highlightGuide: highlightGuide,
            keyboardGeometry: keyboardGeometry
        )
        var coveredTargets: [PianoDemonstrationHandTarget] = []
        var uncoveredKeys = candidateResolution.uncoveredKeys

        for hand in PianoDemonstrationHand.allCases {
            let handCandidates = candidateResolution.candidates.filter { $0.hand == hand }
            if handCandidates.count > PianoDemonstrationFinger.allCases.count {
                uncoveredKeys += handCandidates.map {
                    uncoveredKey(for: $0.note, reason: .tooManyFingers)
                }
                continue
            }
            if handSpanMeters(for: handCandidates) > Self.maximumHandSpanMeters {
                uncoveredKeys += handCandidates.map {
                    uncoveredKey(for: $0.note, reason: .spanExceeded)
                }
                continue
            }

            let handResolution = targets(for: hand, candidates: handCandidates)
            coveredTargets += handResolution.targets
            uncoveredKeys += handResolution.uncoveredKeys
        }

        return PianoDemonstrationHandCoverage(
            guideID: highlightGuide.id,
            coveredTargets: coveredTargets.sorted { lhs, rhs in
                if lhs.hand != rhs.hand { return lhs.hand == .left }
                if lhs.midiNote != rhs.midiNote { return lhs.midiNote < rhs.midiNote }
                return lhs.occurrenceID < rhs.occurrenceID
            },
            uncoveredKeys: uncoveredKeys.sorted { lhs, rhs in
                if lhs.midiNote != rhs.midiNote { return lhs.midiNote < rhs.midiNote }
                if lhs.occurrenceID != rhs.occurrenceID { return lhs.occurrenceID < rhs.occurrenceID }
                return lhs.reason.rawValue < rhs.reason.rawValue
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

        return noteByOccurrenceID.values.sorted { lhs, rhs in
            if lhs.note.midiNote != rhs.note.midiNote {
                return lhs.note.midiNote < rhs.note.midiNote
            }
            return lhs.note.occurrenceID < rhs.note.occurrenceID
        }
    }

    private func currentCandidates(
        highlightGuide: PianoHighlightGuide,
        keyboardGeometry: PianoKeyboardGeometry
    ) -> CandidateResolution {
        var candidates: [Candidate] = []
        var uncoveredKeys: [PianoDemonstrationHandCoverage.UncoveredKey] = []

        for item in currentNotes(in: highlightGuide) {
            guard let hand = demonstrationHand(for: item.note) else {
                uncoveredKeys.append(uncoveredKey(for: item.note, reason: .unknownHand))
                continue
            }
            guard let key = keyboardGeometry.key(for: item.note.midiNote) else {
                uncoveredKeys.append(uncoveredKey(for: item.note, reason: .missingGeometry))
                continue
            }

            candidates.append(Candidate(
                note: item.note,
                hand: hand,
                phase: item.phase,
                contactPositionLocal: SIMD3<Float>(
                    key.localCenter.x,
                    key.surfaceLocalY,
                    key.localCenter.z
                )
            ))
        }

        return CandidateResolution(candidates: candidates, uncoveredKeys: uncoveredKeys)
    }

    private func demonstrationHand(for note: PianoHighlightNote) -> PianoDemonstrationHand? {
        if let assignedHand = PianoDemonstrationHand(scoreHand: note.handAssignment.hand) {
            return assignedHand
        }

        // Grand-staff routing is visual-only: it never changes the score's unresolved hand fact.
        return switch note.staff {
        case 1:
            .right
        case 2:
            .left
        default:
            nil
        }
    }

    private func targets(
        for hand: PianoDemonstrationHand,
        candidates: [Candidate]
    ) -> HandResolution {
        let sortedCandidates = candidates.sorted { lhs, rhs in
            if lhs.note.midiNote != rhs.note.midiNote { return lhs.note.midiNote < rhs.note.midiNote }
            return lhs.note.occurrenceID < rhs.note.occurrenceID
        }
        let fingerOrder: [PianoDemonstrationFinger] = hand == .right
            ? PianoDemonstrationFinger.allCases
            : Array(PianoDemonstrationFinger.allCases.reversed())
        var usedFingers = Set<PianoDemonstrationFinger>()
        var resolvedTargets: [PianoDemonstrationHandTarget] = []
        var uncoveredKeys: [PianoDemonstrationHandCoverage.UncoveredKey] = []

        for candidate in sortedCandidates {
            guard let finger = explicitFinger(for: candidate.note, hand: hand) else { continue }
            guard usedFingers.insert(finger).inserted else {
                uncoveredKeys.append(uncoveredKey(for: candidate.note, reason: .fingeringConflict))
                continue
            }
            resolvedTargets.append(target(for: candidate, finger: finger))
        }

        for (index, candidate) in sortedCandidates.enumerated()
            where explicitFinger(for: candidate.note, hand: hand) == nil
        {
            guard let finger = nearestUnusedFinger(
                to: fingerOrder[min(index, fingerOrder.count - 1)],
                usedFingers: usedFingers
            ) else {
                uncoveredKeys.append(uncoveredKey(for: candidate.note, reason: .fingeringConflict))
                continue
            }
            usedFingers.insert(finger)
            resolvedTargets.append(target(for: candidate, finger: finger))
        }

        return HandResolution(targets: resolvedTargets, uncoveredKeys: uncoveredKeys)
    }

    private func handSpanMeters(for candidates: [Candidate]) -> Float {
        guard let minimumX = candidates.map(\.contactPositionLocal.x).min(),
              let maximumX = candidates.map(\.contactPositionLocal.x).max()
        else {
            return 0
        }
        return maximumX - minimumX
    }

    private func explicitFinger(
        for note: PianoHighlightNote,
        hand: PianoDemonstrationHand
    ) -> PianoDemonstrationFinger? {
        note.fingerings.lazy.compactMap { fingering in
            guard fingeringMatches(fingering.hand, demonstrationHand: hand) else { return nil }
            guard let value = Int(fingering.text), (1 ... 5).contains(value) else { return nil }
            return PianoDemonstrationFinger(rawValue: value)
        }.first
    }

    private func fingeringMatches(
        _ fingeringHand: MusicXMLFingeringHand,
        demonstrationHand: PianoDemonstrationHand
    ) -> Bool {
        switch (fingeringHand, demonstrationHand) {
        case (.unspecified, _), (.left, .left), (.right, .right):
            true
        case (.left, .right), (.right, .left), (.unsupported, _):
            false
        }
    }

    private func nearestUnusedFinger(
        to preferredFinger: PianoDemonstrationFinger,
        usedFingers: Set<PianoDemonstrationFinger>
    ) -> PianoDemonstrationFinger? {
        PianoDemonstrationFinger.allCases
            .filter { usedFingers.contains($0) == false }
            .min { lhs, rhs in
                let lhsDistance = abs(lhs.rawValue - preferredFinger.rawValue)
                let rhsDistance = abs(rhs.rawValue - preferredFinger.rawValue)
                if lhsDistance != rhsDistance { return lhsDistance < rhsDistance }
                return lhs.rawValue < rhs.rawValue
            }
    }

    private func target(
        for candidate: Candidate,
        finger: PianoDemonstrationFinger
    ) -> PianoDemonstrationHandTarget {
        PianoDemonstrationHandTarget(
            occurrenceID: candidate.note.occurrenceID,
            hand: candidate.hand,
            finger: finger,
            midiNote: candidate.note.midiNote,
            phase: candidate.phase,
            contactPositionLocal: candidate.contactPositionLocal,
            velocity: candidate.note.velocity
        )
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
        case .left:
            self = .left
        case .right:
            self = .right
        case .unknown:
            return nil
        }
    }
}

private struct NoteState {
    let note: PianoHighlightNote
    let phase: PianoDemonstrationTouchPhase
}

private struct Candidate {
    let note: PianoHighlightNote
    let hand: PianoDemonstrationHand
    let phase: PianoDemonstrationTouchPhase
    let contactPositionLocal: SIMD3<Float>
}

private struct CandidateResolution {
    let candidates: [Candidate]
    let uncoveredKeys: [PianoDemonstrationHandCoverage.UncoveredKey]
}

private struct HandResolution {
    let targets: [PianoDemonstrationHandTarget]
    let uncoveredKeys: [PianoDemonstrationHandCoverage.UncoveredKey]
}
