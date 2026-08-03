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

    func recordPerformanceNotation(elementName: String, attributes: [String: String]) {
        guard state.isInNote else { return }
        let rawElementToken = elementName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard rawElementToken.isEmpty == false else { return }
        let kind = MusicXMLPerformanceNotationKind(rawValue: rawElementToken) ?? .other
        let pending = MusicXMLParserDelegateState.PendingPerformanceNotation(
            sourceOrdinal: nextNoteNotationSourceOrdinal(),
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

    func recordTie(sourceElement: MusicXMLTieSourceElement, attributes: [String: String]) {
        guard state.isInNote else { return }
        state.noteTies.append(.init(
            sourceOrdinal: nextNoteNotationSourceOrdinal(),
            sourceElement: sourceElement,
            typeToken: normalizedNotationToken(attributes["type"]),
            numberToken: normalizedNotationToken(attributes["number"]),
            placementToken: normalizedNotationToken(attributes["placement"])
        ))
    }

    func recordSlur(attributes: [String: String]) {
        guard state.isInNote else { return }
        state.noteSlurs.append(.init(
            sourceOrdinal: nextNoteNotationSourceOrdinal(),
            typeToken: normalizedNotationToken(attributes["type"]),
            numberToken: normalizedNotationToken(attributes["number"]),
            placementToken: normalizedNotationToken(attributes["placement"])
        ))
    }

    func recordTuplet(attributes: [String: String]) {
        guard state.isInNote else { return }
        state.noteTuplets.append(.init(
            sourceOrdinal: nextNoteNotationSourceOrdinal(),
            typeToken: normalizedNotationToken(attributes["type"]),
            numberToken: normalizedNotationToken(attributes["number"]),
            bracketToken: normalizedNotationToken(attributes["bracket"]),
            placementToken: normalizedNotationToken(attributes["placement"])
        ))
    }

    private func nextNoteNotationSourceOrdinal() -> Int {
        defer { state.nextNoteNotationSourceOrdinal += 1 }
        return state.nextNoteNotationSourceOrdinal
    }

    func recordFingering(attributes: [String: String]) {
        guard state.isInNote, state.isInTechnical else { return }
        state.noteFingerings.append(.init(
            sourceOrdinal: nextNoteNotationSourceOrdinal(),
            substitution: MusicXMLFingeringOption(sourceToken: attributes["substitution"]),
            alternate: MusicXMLFingeringOption(sourceToken: attributes["alternate"]),
            placementToken: normalizedNotationToken(attributes["placement"]),
            hand: MusicXMLFingeringHand(sourceToken: attributes["hand"]),
            text: nil
        ))
        state.currentFingeringIndex = state.noteFingerings.indices.last
    }

    func finalizeFingering(text: String) {
        guard let index = state.currentFingeringIndex,
              state.noteFingerings.indices.contains(index)
        else {
            return
        }
        state.noteFingerings[index].text = normalizedNotationToken(text)
        state.currentFingeringIndex = nil
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
        let noteType: MusicXMLNoteType?
        if let typeToken = state.noteType {
            guard let parsedType = MusicXMLNoteType(musicXMLToken: typeToken) else {
                recordWrittenRhythmError(.unsupportedType)
                return
            }
            noteType = parsedType
        } else {
            noteType = nil
        }
        guard state.noteIsMeasureRest || noteType != nil else {
            recordWrittenRhythmError(.missingType)
            return
        }

        let duration: Int
        if state.noteIsGrace {
            duration = 0
        } else {
            guard let parsedDuration = state.noteDuration else {
                recordWrittenRhythmError(.missingDuration)
                return
            }
            guard parsedDuration > 0 else {
                recordWrittenRhythmError(.invalidDuration)
                return
            }
            duration = parsedDuration
        }

        let timeModification = timeModification()
        let writtenRhythm: MusicXMLWrittenRhythm? = noteType.map {
            MusicXMLWrittenRhythm(
                noteType: $0,
                dotCount: state.noteDotCount,
                timeModification: timeModification
            )
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

        func notationSourceID(_ ordinal: Int) -> MusicXMLPerformanceNotationSourceID {
            MusicXMLPerformanceNotationSourceID(sourceNoteID: sourceID, sourceOrdinal: ordinal)
        }
        let ties = state.noteTies.map { pending in
            MusicXMLTie(
                sourceID: notationSourceID(pending.sourceOrdinal),
                sourceElement: pending.sourceElement,
                typeToken: pending.typeToken,
                numberToken: pending.numberToken,
                placementToken: pending.placementToken
            )
        }
        let slurs = state.noteSlurs.map { pending in
            MusicXMLSlur(
                sourceID: notationSourceID(pending.sourceOrdinal),
                typeToken: pending.typeToken,
                numberToken: pending.numberToken,
                placementToken: pending.placementToken
            )
        }
        let tuplets = state.noteTuplets.map { pending in
            MusicXMLTuplet(
                sourceID: notationSourceID(pending.sourceOrdinal),
                typeToken: pending.typeToken,
                numberToken: pending.numberToken,
                bracketToken: pending.bracketToken,
                placementToken: pending.placementToken
            )
        }
        let performanceNotations = state.notePerformanceNotations.map { pending in
            MusicXMLPerformanceNotation(
                sourceID: notationSourceID(pending.sourceOrdinal),
                kind: pending.kind,
                rawElementToken: pending.rawElementToken,
                typeToken: pending.typeToken,
                numberToken: pending.numberToken,
                placementToken: pending.placementToken,
                textToken: pending.textToken,
                attributes: pending.attributes
            )
        }
        let fingerings = state.noteFingerings.compactMap { pending -> MusicXMLFingering? in
            guard let text = pending.text else { return nil }
            return MusicXMLFingering(
                sourceID: MusicXMLFingeringSourceID(
                    sourceNoteID: sourceID,
                    sourceOrdinal: pending.sourceOrdinal
                ),
                text: text,
                substitution: pending.substitution,
                alternate: pending.alternate,
                placementToken: pending.placementToken,
                hand: pending.hand,
                provenance: .score
            )
        }

        state.notes.append(
            MusicXMLNoteEvent(
                sourceID: sourceID,
                partID: state.currentPartID,
                measureNumber: state.currentMeasureNumber,
                tick: startTick,
                durationTicks: duration,
                hasExplicitDuration: state.noteDuration != nil,
                writtenPitch: writtenPitch,
                writtenRhythm: writtenRhythm,
                noteheadToken: state.noteNoteheadToken,
                midiNote: midiNote,
                isRest: state.noteIsRest,
                isMeasureRest: state.noteIsMeasureRest,
                isPrintObjectVisible: state.noteIsPrintObjectVisible,
                isChord: state.noteIsChord,
                isGrace: state.noteIsGrace,
                graceSlash: state.noteGraceSlash,
                graceStealTimePrevious: state.noteGraceStealTimePrevious,
                graceStealTimeFollowing: state.noteGraceStealTimeFollowing,
                graceMakeTimeTicks: state.noteGraceMakeTimeTicks,
                ties: ties,
                slurs: slurs,
                tuplets: tuplets,
                stem: state.noteStem,
                beams: state.noteBeams,
                staff: state.noteStaff,
                voice: state.noteVoice,
                attackTicks: state.noteAttackTicks,
                releaseTicks: state.noteReleaseTicks,
                dynamicsOverrideVelocity: state.noteDynamicsOverrideVelocity,
                articulations: state.noteArticulations,
                arpeggiate: state.noteArpeggiate,
                performanceNotations: performanceNotations,
                fingerings: fingerings
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
                    source: .noteNotations,
                    placementToken: state.noteFermataPlacementToken
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

    private func timeModification() -> MusicXMLTimeModification? {
        if state.noteTimeModificationActualNotes != nil ||
            state.noteTimeModificationNormalNotes != nil ||
            state.noteTimeModificationNormalType != nil ||
            state.noteTimeModificationNormalDotCount > 0
        {
            MusicXMLTimeModification(
                actualNotes: state.noteTimeModificationActualNotes,
                normalNotes: state.noteTimeModificationNormalNotes,
                normalTypeToken: state.noteTimeModificationNormalType,
                normalDotCount: state.noteTimeModificationNormalDotCount
            )
        } else {
            nil
        }
    }

    private func recordWrittenRhythmError(_ failure: MusicXMLWrittenRhythmFailure) {
        if state.writtenRhythmError == nil {
            state.writtenRhythmError = .invalidWrittenRhythm(failure)
        }
    }

    static func makeMIDINote(_ pitch: MusicXMLWrittenPitch) -> Int? {
        let roundedAlter = pitch.alter.rounded()
        guard abs(pitch.alter - roundedAlter) < 0.000_001 else { return nil }
        let stepBase: [String: Int] = [
            "C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11,
        ]
        guard let base = stepBase[pitch.step] else { return nil }
        let value = (pitch.octave + 1) * 12 + base + Int(roundedAlter)
        return (0 ... 127).contains(value) ? value : nil
    }
}
