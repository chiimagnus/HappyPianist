import Foundation

protocol PracticeStepBuilderProtocol {
    func buildSteps(from score: MusicXMLScore, expressivity: MusicXMLExpressivityOptions) -> PracticeStepBuildResult
}

extension PracticeStepBuilderProtocol {
    func buildSteps(from score: MusicXMLScore) -> PracticeStepBuildResult {
        buildSteps(from: score, expressivity: MusicXMLExpressivityOptions())
    }
}

struct PracticeStepBuilder: PracticeStepBuilderProtocol {
    private let playableRange = 21 ... 108

    func buildSteps(from score: MusicXMLScore, expressivity: MusicXMLExpressivityOptions) -> PracticeStepBuildResult {
        var grouped: [Int: [Int: (staff: Int?, velocity: UInt8, onTickOffset: Int, fingeringText: String?)]] =
            [:] // tick -> midi -> (staff, velocity, onTickOffset, fingeringText)
        var unsupportedNoteCount = 0
        let velocityResolver = MusicXMLVelocityResolver(
            dynamicEvents: score.dynamicEvents,
            wedgeEvents: score.wedgeEvents,
            wedgeEnabled: expressivity.wedgeEnabled
        )
        let graceOnTickByNoteIndex = expressivity.graceEnabled ? computeGraceOnTickByNoteIndex(notes: score.notes) : [:]
        let arpeggiateOffsetByNoteIndex = expressivity
            .arpeggiateEnabled ? computeArpeggiateOffsetTicksByNoteIndex(notes: score.notes) : [:]

        for (index, noteEvent) in score.notes.enumerated() {
            if noteEvent.isRest {
                continue
            }

            if noteEvent.isGrace, expressivity.graceEnabled == false {
                continue
            }

            if noteEvent.tieStop {
                continue
            }

            guard let midiNote = noteEvent.midiNote else {
                continue
            }

            guard playableRange.contains(midiNote) else {
                unsupportedNoteCount += 1
                continue
            }

            let velocity = velocityResolver.velocity(for: noteEvent)
            let effectiveTick = graceOnTickByNoteIndex[index] ?? noteEvent.tick
            let onTickOffset = max(0, arpeggiateOffsetByNoteIndex[index] ?? 0)
            var map = grouped[effectiveTick] ?? [:]
            if map[midiNote] == nil {
                map[midiNote] = (
                    staff: noteEvent.staff,
                    velocity: velocity,
                    onTickOffset: onTickOffset,
                    fingeringText: noteEvent.fingeringText
                )
            }
            grouped[effectiveTick] = map
        }

        let steps = grouped.keys.sorted().map { tick in
            let notesMap = grouped[tick] ?? [:]
            let notes = notesMap.keys.sorted().map { midiNote in
                let entry = notesMap[midiNote]
                return PracticeStepNote(
                    midiNote: midiNote,
                    staff: entry?.staff,
                    velocity: entry?.velocity ?? 96,
                    onTickOffset: entry?.onTickOffset ?? 0,
                    fingeringText: entry?.fingeringText
                )
            }
            return PracticeStep(tick: tick, notes: notes)
        }

        return PracticeStepBuildResult(steps: steps, unsupportedNoteCount: unsupportedNoteCount)
    }

    private struct GraceKey: Hashable {
        let partID: String
        let staff: Int
        let voice: Int
        let tick: Int
    }

    private func computeGraceOnTickByNoteIndex(notes: [MusicXMLNoteEvent]) -> [Int: Int] {
        var graceIndicesByKey: [GraceKey: [Int]] = [:]
        graceIndicesByKey.reserveCapacity(32)

        var followingDurationTicksByKey: [GraceKey: Int] = [:]
        followingDurationTicksByKey.reserveCapacity(32)

        for (index, note) in notes.enumerated() {
            let staff = note.staff ?? 1
            let voice = note.voice ?? 1
            let key = GraceKey(partID: note.partID, staff: staff, voice: voice, tick: note.tick)

            if note.isGrace {
                graceIndicesByKey[key, default: []].append(index)
            } else if followingDurationTicksByKey[key] == nil, note.isRest == false {
                followingDurationTicksByKey[key] = max(0, note.durationTicks)
            }
        }

        var result: [Int: Int] = [:]
        result.reserveCapacity(graceIndicesByKey.values.reduce(0) { $0 + $1.count })

        for (key, indices) in graceIndicesByKey {
            guard let followingDuration = followingDurationTicksByKey[key], followingDuration > 0 else { continue }

            let stealFraction: Double = indices.compactMap { notes[$0].graceStealTimeFollowing }.first
                ?? indices.compactMap { notes[$0].graceStealTimePrevious }.first
                ?? 0.25

            let totalStolenTicks = max(
                1,
                min(followingDuration - 1, Int((Double(followingDuration) * stealFraction).rounded()))
            )
            let startTick = max(0, key.tick - totalStolenTicks)

            let slice = max(1, totalStolenTicks / max(1, indices.count))
            var cursor = startTick
            for (i, noteIndex) in indices.enumerated() {
                var duration = slice
                if i == indices.count - 1 {
                    duration = max(1, key.tick - cursor)
                }
                if notes[noteIndex].graceSlash {
                    duration = max(1, duration / 2)
                }
                result[noteIndex] = cursor
                cursor += duration
            }
        }

        return result
    }

    private struct ArpeggiateKey: Hashable {
        let partID: String
        let staff: Int
        let tick: Int
    }

    private func computeArpeggiateOffsetTicksByNoteIndex(notes: [MusicXMLNoteEvent]) -> [Int: Int] {
        struct Candidate {
            let index: Int
            let midi: Int
            let durationTicks: Int
        }

        var directionTokenByKey: [ArpeggiateKey: String?] = [:]
        directionTokenByKey.reserveCapacity(32)

        for note in notes {
            guard note.isRest == false else { continue }
            guard note.isGrace == false else { continue }
            guard note.arpeggiate != nil else { continue }

            let staff = note.staff ?? 1
            let key = ArpeggiateKey(partID: note.partID, staff: staff, tick: note.tick)
            if directionTokenByKey[key] == nil {
                directionTokenByKey[key] = note.arpeggiate?.directionToken
            }
        }

        guard directionTokenByKey.isEmpty == false else { return [:] }

        var candidatesByKey: [ArpeggiateKey: [Candidate]] = [:]
        candidatesByKey.reserveCapacity(32)

        for (index, note) in notes.enumerated() {
            guard note.isRest == false else { continue }
            guard note.isGrace == false else { continue }
            guard let midi = note.midiNote else { continue }

            let staff = note.staff ?? 1
            let key = ArpeggiateKey(partID: note.partID, staff: staff, tick: note.tick)
            guard directionTokenByKey[key] != nil else { continue }
            candidatesByKey[key, default: []].append(
                Candidate(
                    index: index,
                    midi: midi,
                    durationTicks: max(0, note.durationTicks)
                )
            )
        }

        guard candidatesByKey.isEmpty == false else { return [:] }

        var offsets: [Int: Int] = [:]
        offsets.reserveCapacity(candidatesByKey.values.reduce(0) { $0 + $1.count })

        for (key, candidates) in candidatesByKey {
            guard candidates.count >= 2 else {
                offsets[candidates[0].index] = 0
                continue
            }

            let durationTicks = candidates.map(\.durationTicks).max() ?? 0
            guard durationTicks > 0 else {
                for candidate in candidates {
                    offsets[candidate.index] = 0
                }
                continue
            }

            let spreadUpperBound = min(durationTicks - 1, MusicXMLTempoMap.ticksPerQuarter / 16)
            let totalSpreadTicks = max(1, min(spreadUpperBound, durationTicks / 4))
            let step = max(1, totalSpreadTicks / max(1, candidates.count - 1))
            let directionToken = (directionTokenByKey[key] ?? nil)?.lowercased()
            let ordered = (directionToken == "down")
                ? candidates.sorted { $0.midi > $1.midi }
                : candidates.sorted { $0.midi < $1.midi }

            var cursor = 0
            for (i, candidate) in ordered.enumerated() {
                offsets[candidate.index] = cursor
                if i < ordered.count - 1 {
                    cursor = min(totalSpreadTicks, cursor + step)
                }
            }
        }

        return offsets
    }
}
