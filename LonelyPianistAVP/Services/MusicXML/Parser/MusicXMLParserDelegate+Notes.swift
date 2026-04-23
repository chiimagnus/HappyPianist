import Foundation

extension MusicXMLParserDelegate {
    func parseNotePerformanceOffsetTicks(_ rawValue: String?) -> Int? {
        guard let rawValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              rawValue.isEmpty == false
        else {
            return nil
        }

        guard let offsetInDivisions = Double(rawValue), offsetInDivisions.isFinite else {
            return nil
        }

        let divisions = Double(state.partDivisions[state.currentPartID] ?? 1)
        guard divisions > 0 else { return nil }

        let ticksPerDivision = Double(state.normalizedTicksPerQuarter) / divisions
        let offsetTicks = Int(offsetInDivisions * ticksPerDivision)
        return offsetTicks == 0 ? nil : offsetTicks
    }

    func deriveDurationTicksFromTypeAndTupletIfPossible() -> Int? {
        guard let rawType = state.noteType?.trimmingCharacters(in: .whitespacesAndNewlines),
              rawType.isEmpty == false
        else {
            return nil
        }

        let type = rawType.lowercased()
        let quarters: Double? = switch type {
            case "whole":
                4
            case "half":
                2
            case "quarter":
                1
            case "eighth":
                0.5
            case "16th":
                0.25
            case "32nd":
                0.125
            case "64th":
                0.0625
            case "128th":
                0.03125
            default:
                nil
        }

        guard let quarters else { return nil }

        var durationTicks = quarters * Double(state.normalizedTicksPerQuarter)
        if state.noteDotCount > 0 {
            let dots = min(6, state.noteDotCount)
            let multiplier = 2.0 - (1.0 / pow(2.0, Double(dots)))
            durationTicks *= multiplier
        }

        if let actual = state.noteTimeModificationActualNotes,
           let normal = state.noteTimeModificationNormalNotes,
           actual > 0,
           normal > 0
        {
            durationTicks *= Double(normal) / Double(actual)
        }

        let ticks = Int(durationTicks.rounded())
        return ticks > 0 ? ticks : nil
    }

    func finalizeNote() {
        let duration: Int
        if let rawDuration = state.noteDuration {
            duration = rawDuration
        } else if state.noteIsGrace {
            duration = 0
        } else if let derivedDuration = deriveDurationTicksFromTypeAndTupletIfPossible() {
            duration = derivedDuration
        } else {
            return
        }

        let currentTick = state.partTick[state.currentPartID] ?? state.currentMeasureStartTick
        let startTick: Int
        if state.noteIsChord {
            startTick = state.partLastNonChordStartTick[state.currentPartID] ?? currentTick
        } else if state.noteIsGrace {
            startTick = currentTick
        } else {
            startTick = currentTick
            state.partLastNonChordStartTick[state.currentPartID] = startTick
            state.partTick[state.currentPartID] = currentTick + duration
        }

        let midiNote: Int? = if state.noteIsRest {
            nil
        } else {
            Self.makeMIDINote(step: state.noteStep, alter: state.noteAlter ?? 0, octave: state.noteOctave)
        }

        state.notes.append(
            MusicXMLNoteEvent(
                partID: state.currentPartID,
                measureNumber: state.currentMeasureNumber,
                tick: startTick,
                durationTicks: duration,
                midiNote: midiNote,
                isRest: state.noteIsRest,
                isChord: state.noteIsChord,
                isGrace: state.noteIsGrace,
                tieStart: state.noteTieStart,
                tieStop: state.noteTieStop,
                staff: state.noteStaff,
                voice: state.noteVoice,
                attackTicks: state.noteAttackTicks,
                releaseTicks: state.noteReleaseTicks,
                dynamicsOverrideVelocity: state.noteDynamicsOverrideVelocity,
                articulations: state.noteArticulations
            )
        )

        let noteEndTick = startTick + duration
        let currentMax = state.partMeasureMaxTick[state.currentPartID] ?? state.currentMeasureStartTick
        state.partMeasureMaxTick[state.currentPartID] = max(
            currentMax,
            noteEndTick,
            state.partTick[state.currentPartID] ?? currentTick
        )
    }

    static func makeMIDINote(step: String?, alter: Int, octave: Int?) -> Int? {
        guard let step, let octave else { return nil }
        let stepBase: [String: Int] = [
            "C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11,
        ]
        guard let base = stepBase[step] else { return nil }
        return (octave + 1) * 12 + base + alter
    }
}
