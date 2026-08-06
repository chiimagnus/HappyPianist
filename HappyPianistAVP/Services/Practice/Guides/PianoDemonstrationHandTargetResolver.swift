import MusicXML
import Practice

struct PianoDemonstrationHandTargetResolver {
    private static let maximumHandSpanMeters: Float = 0.20

    func resolve(
        highlightGuide: PianoHighlightGuide?,
        keyboardGeometry: PianoKeyboardGeometry?
    ) -> PianoDemonstrationHandTargets {
        guard let highlightGuide, let keyboardGeometry else {
            return .empty
        }

        let candidates = currentCandidates(
            highlightGuide: highlightGuide,
            keyboardGeometry: keyboardGeometry
        )
        var resolvedTargets: [PianoDemonstrationHandTarget] = []

        for hand in PianoDemonstrationHand.allCases {
            let handCandidates = candidates.filter { $0.hand == hand }
            guard handCandidates.count <= PianoDemonstrationFinger.allCases.count,
                  handSpanMeters(for: handCandidates) <= Self.maximumHandSpanMeters
            else {
                continue
            }
            resolvedTargets += targets(for: hand, candidates: handCandidates)
        }

        return PianoDemonstrationHandTargets(
            guideID: highlightGuide.id,
            targets: resolvedTargets.sorted { lhs, rhs in
                if lhs.hand != rhs.hand { return lhs.hand == .left }
                if lhs.midiNote != rhs.midiNote { return lhs.midiNote < rhs.midiNote }
                return lhs.occurrenceID < rhs.occurrenceID
            },
            releasedMIDINotes: highlightGuide.releasedMIDINotes
        )
    }

    private func currentCandidates(
        highlightGuide: PianoHighlightGuide,
        keyboardGeometry: PianoKeyboardGeometry
    ) -> [Candidate] {
        var noteByOccurrenceID: [String: (note: PianoHighlightNote, phase: PianoDemonstrationTouchPhase)] = [:]

        for note in highlightGuide.activeNotes {
            noteByOccurrenceID[note.occurrenceID] = (note, .held)
        }
        for note in highlightGuide.triggeredNotes {
            noteByOccurrenceID[note.occurrenceID] = (note, .triggered)
        }

        return noteByOccurrenceID.values.compactMap { item in
            guard let hand = demonstrationHand(for: item.note) else {
                return nil
            }
            guard let key = keyboardGeometry.key(for: item.note.midiNote) else {
                return nil
            }

            return Candidate(
                note: item.note,
                hand: hand,
                phase: item.phase,
                contactPositionLocal: SIMD3<Float>(
                    key.localCenter.x,
                    key.surfaceLocalY,
                    key.localCenter.z
                )
            )
        }
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
    ) -> [PianoDemonstrationHandTarget] {
        let sortedCandidates = candidates.sorted { lhs, rhs in
            if lhs.note.midiNote != rhs.note.midiNote { return lhs.note.midiNote < rhs.note.midiNote }
            return lhs.note.occurrenceID < rhs.note.occurrenceID
        }
        let fingerOrder: [PianoDemonstrationFinger] = hand == .right
            ? PianoDemonstrationFinger.allCases
            : Array(PianoDemonstrationFinger.allCases.reversed())
        var usedFingers = Set<PianoDemonstrationFinger>()
        var targets: [PianoDemonstrationHandTarget] = []

        for candidate in sortedCandidates {
            guard let finger = explicitFinger(for: candidate.note, hand: hand) else { continue }
            guard usedFingers.insert(finger).inserted else { continue }
            targets.append(target(for: candidate, finger: finger))
        }

        for (index, candidate) in sortedCandidates.enumerated() where explicitFinger(for: candidate.note, hand: hand) == nil {
            guard let finger = nearestUnusedFinger(
                to: fingerOrder[min(index, fingerOrder.count - 1)],
                usedFingers: usedFingers
            ) else {
                continue
            }
            usedFingers.insert(finger)
            targets.append(target(for: candidate, finger: finger))
        }

        return targets
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

private struct Candidate {
    let note: PianoHighlightNote
    let hand: PianoDemonstrationHand
    let phase: PianoDemonstrationTouchPhase
    let contactPositionLocal: SIMD3<Float>
}
