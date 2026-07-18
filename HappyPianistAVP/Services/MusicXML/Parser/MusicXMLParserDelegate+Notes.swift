import Foundation

extension MusicXMLParserDelegate {
    func parseGraceStealFraction(_ rawValue: String?) -> Double? {
        guard let rawValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              rawValue.isEmpty == false,
              let value = Double(rawValue),
              value.isFinite
        else {
            return nil
        }

        let normalized: Double = if value > 1 {
            value / 100.0
        } else {
            value
        }

        let clamped = min(1, max(0, normalized))
        return clamped == 0 ? nil : clamped
    }

    func parseGraceMakeTimeTicks(_ rawValue: String?) -> Int? {
        guard let ticks = parseNotePerformanceOffsetTicks(rawValue), ticks > 0 else {
            return nil
        }
        return ticks
    }

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


    func recordPerformanceNotation(elementName: String, attributes: [String: String]) {
        guard state.isInNote else { return }
        let rawElementToken = elementName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard rawElementToken.isEmpty == false else { return }
        let kind = MusicXMLPerformanceNotationKind(rawValue: rawElementToken) ?? .other
        let pending = MusicXMLParserDelegateState.PendingPerformanceNotation(
            kind: kind,
            rawElementToken: rawElementToken,
            typeToken: normalizedNotationToken(attributes["type"]),
            numberToken: normalizedNotationToken(attributes["number"]),
            placementToken: normalizedNotationToken(attributes["placement"]),
            textToken: nil,
            attributes: attributes
        )
        state.notePerformanceNotations.append(pending)
        state.currentPerformanceNotationIndexByElement[rawElementToken] = state.notePerformanceNotations.count - 1
    }

    func finalizePerformanceNotationText(elementName: String, text: String) {
        let rawElementToken = elementName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let index = state.currentPerformanceNotationIndexByElement.removeValue(forKey: rawElementToken),
              state.notePerformanceNotations.indices.contains(index)
        else {
            return
        }
        let normalizedText = normalizedNotationToken(text)
        state.notePerformanceNotations[index].textToken = normalizedText
    }

    func shouldRecordUnsupportedOrnament(elementName: String) -> Bool {
        guard state.isInNote, state.isInNoteOrnaments else { return false }
        let token = elementName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return token.isEmpty == false && token != "ornaments"
    }

    private func normalizedNotationToken(_ rawValue: String?) -> String? {
        let token = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return token.isEmpty ? nil : token
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

        let writtenPitch: MusicXMLWrittenPitch? = if state.noteIsRest {
            nil
        } else if let step = state.noteStep, let octave = state.noteOctave {
            MusicXMLWrittenPitch(
                step: step,
                octave: octave,
                alter: state.noteAlter ?? 0,
                accidentalToken: state.noteAccidentalToken
            )
        } else {
            nil
        }
        let midiNote = writtenPitch.flatMap(Self.makeMIDINote)

        let sourceID = MusicXMLSourceNoteID(
            partID: state.currentPartID,
            sourceMeasureIndex: state.currentMeasureIndex,
            sourceMeasureNumberToken: state.currentMeasureNumberToken,
            staff: state.noteStaff,
            voice: state.noteVoice,
            sourceOrdinal: state.currentSourceNoteOrdinal
        )
        state.currentSourceNoteOrdinal += 1

        let performanceNotations = state.notePerformanceNotations.enumerated().map { ordinal, pending in
            MusicXMLPerformanceNotation(
                sourceID: MusicXMLPerformanceNotationSourceID(
                    sourceNoteID: sourceID,
                    sourceOrdinal: ordinal
                ),
                kind: pending.kind,
                rawElementToken: pending.rawElementToken,
                typeToken: pending.typeToken,
                numberToken: pending.numberToken,
                placementToken: pending.placementToken,
                textToken: pending.textToken,
                attributes: pending.attributes
            )
        }

        state.notes.append(
            MusicXMLNoteEvent(
                sourceID: sourceID,
                partID: state.currentPartID,
                measureNumber: state.currentMeasureNumber,
                tick: startTick,
                durationTicks: duration,
                writtenPitch: writtenPitch,
                midiNote: midiNote,
                isRest: state.noteIsRest,
                isChord: state.noteIsChord,
                isGrace: state.noteIsGrace,
                graceSlash: state.noteGraceSlash,
                graceStealTimePrevious: state.noteGraceStealTimePrevious,
                graceStealTimeFollowing: state.noteGraceStealTimeFollowing,
                graceMakeTimeTicks: state.noteGraceMakeTimeTicks,
                tieStart: state.noteTieStart,
                tieStop: state.noteTieStop,
                staff: state.noteStaff,
                voice: state.noteVoice,
                attackTicks: state.noteAttackTicks,
                releaseTicks: state.noteReleaseTicks,
                dynamicsOverrideVelocity: state.noteDynamicsOverrideVelocity,
                articulations: state.noteArticulations,
                arpeggiate: state.noteArpeggiate,
                performanceNotations: performanceNotations,
                fingeringText: state.noteFingeringText,
                dotCount: state.noteDotCount
            )
        )

        if state.noteHasFermata {
            state.fermataEvents.append(
                MusicXMLFermataEvent(
                    tick: startTick,
                    scope: MusicXMLEventScope(
                        partID: state.currentPartID,
                        staff: state.noteStaff,
                        voice: state.noteVoice
                    ),
                    source: .noteNotations
                )
            )
        }

        let noteEndTick = startTick + duration
        let currentMax = state.partMeasureMaxTick[state.currentPartID] ?? state.currentMeasureStartTick
        state.partMeasureMaxTick[state.currentPartID] = max(
            currentMax,
            noteEndTick,
            state.partTick[state.currentPartID] ?? currentTick
        )
    }

    static func makeMIDINote(_ pitch: MusicXMLWrittenPitch) -> Int? {
        let roundedAlter = pitch.alter.rounded()
        guard abs(pitch.alter - roundedAlter) < 0.000_001 else { return nil }
        let stepBase: [String: Int] = [
            "C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11,
        ]
        guard let base = stepBase[pitch.step] else { return nil }
        let value = (pitch.octave + 1) * 12 + base + Int(roundedAlter)
        return (0...127).contains(value) ? value : nil
    }
}
