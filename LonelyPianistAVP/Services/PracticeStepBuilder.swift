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
        var grouped: [Int: [Int: (staff: Int?, velocity: UInt8)]] = [:] // tick -> midi -> (staff, velocity)
        var unsupportedNoteCount = 0
        let velocityResolver = MusicXMLVelocityResolver(
            dynamicEvents: score.dynamicEvents,
            wedgeEvents: score.wedgeEvents,
            wedgeEnabled: expressivity.wedgeEnabled
        )
        let graceOnTickByNoteIndex = expressivity.graceEnabled ? computeGraceOnTickByNoteIndex(notes: score.notes) : [:]

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
            var map = grouped[effectiveTick] ?? [:]
            if map[midiNote] == nil {
                map[midiNote] = (staff: noteEvent.staff, velocity: velocity)
            }
            grouped[effectiveTick] = map
        }

        let steps = grouped.keys.sorted().map { tick in
            let notesMap = grouped[tick] ?? [:]
            let notes = notesMap.keys.sorted().map { midiNote in
                let entry = notesMap[midiNote]
                return PracticeStepNote(midiNote: midiNote, staff: entry?.staff, velocity: entry?.velocity ?? 96)
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
        result.reserveCapacity(graceIndicesByKey.values.reduce(0, { $0 + $1.count }))

        for (key, indices) in graceIndicesByKey {
            guard let followingDuration = followingDurationTicksByKey[key], followingDuration > 0 else { continue }

            let stealFraction: Double = indices.compactMap { notes[$0].graceStealTimeFollowing }.first
                ?? indices.compactMap { notes[$0].graceStealTimePrevious }.first
                ?? 0.25

            let totalStolenTicks = max(1, min(followingDuration - 1, Int((Double(followingDuration) * stealFraction).rounded())))
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
}
