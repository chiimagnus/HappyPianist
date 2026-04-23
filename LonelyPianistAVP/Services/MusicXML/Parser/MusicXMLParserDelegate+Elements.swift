import Foundation

extension MusicXMLParserDelegate {
    func handleStartElement(_ elementName: String, attributes attributeDict: [String: String]) {
        switch elementName {
            case "score-partwise", "score-timewise":
                if state.scoreVersion == nil {
                    state.scoreVersion = attributeDict["version"]
                }
            case "part":
                state.currentPartID = attributeDict["id"] ?? "P1"
                if state.partDivisions[state.currentPartID] == nil {
                    state.partDivisions[state.currentPartID] = 1
                }
                state.currentMeasureIndex = 0
                state.currentMeasureNumberToken = nil
                state.currentMeasureNumber = 0
                state.currentMeasureStartTick = state.partTick[state.currentPartID] ?? 0
                state.partMeasureMaxTick[state.currentPartID] = state.currentMeasureStartTick
            case "measure":
                state.currentMeasureIndex += 1
                state.currentMeasureNumber = state.currentMeasureIndex
                state.currentMeasureNumberToken = attributeDict["number"]
                state.currentMeasureStartTick = state.partTick[state.currentPartID] ?? 0
                state.partMeasureMaxTick[state.currentPartID] = state.currentMeasureStartTick
                state.partLastNonChordStartTick[state.currentPartID] = nil
            case "attributes":
                state.isInAttributes = true
            case "time":
                if state.isInAttributes {
                    state.isInTime = true
                    state.timeBeats = nil
                    state.timeBeatType = nil
                }
            case "key":
                if state.isInAttributes {
                    state.isInKey = true
                    state.keyFifths = nil
                    state.keyModeToken = nil
                }
            case "clef":
                if state.isInAttributes {
                    state.isInClef = true
                    state.clefSignToken = nil
                    state.clefLine = nil
                    state.clefOctaveChange = nil
                    state.clefNumberToken = attributeDict["number"]
                }
            case "direction":
                state.isInDirection = true
                state.currentDirectionOffsetTicks = 0
                state.currentDirectionMeasureStartTick = state.currentMeasureStartTick
                state.currentDirectionTempoStartIndex = state.rawTempoEventsByPart[state.currentPartID]?.count ?? 0
                state.currentDirectionSoundStartIndex = state.soundDirectives.count
                state.currentDirectionPedalStartIndex = state.pedalEvents.count
                state.currentDirectionDynamicStartIndex = state.dynamicEvents.count
                state.currentDirectionWedgeStartIndex = state.wedgeEvents.count
                state.currentDirectionFermataStartIndex = state.fermataEvents.count
                state.currentDirectionSoundOffsetTempoOverrideTicksByIndex = [:]
                state.currentDirectionSoundOffsetSoundOverrideTicksByIndex = [:]
                state.currentDirectionSoundOffsetPedalOverrideTicksByIndex = [:]
                state.currentDirectionStaff = nil
                state.isInDirectionTypeDynamics = false
            case "direction-type":
                break
            case "dynamics":
                if state.isInDirection {
                    state.isInDirectionTypeDynamics = true
                }
            case "pedal":
                recordPedalEvent(attributes: attributeDict)
            case "wedge":
                recordWedgeEvent(attributes: attributeDict)
            case "offset":
                if state.isInDirection, state.isInSound == false {
                    state.currentOffsetAppliesToSound = attributeDict["sound"]?.lowercased() == "yes"
                }
            case "barline":
                state.isInBarline = true
            case "repeat":
                if state.isInBarline,
                   let rawDirection = attributeDict["direction"],
                   let direction = MusicXMLRepeatDirection(rawValue: rawDirection)
                {
                    state.repeatDirectives.append(
                        MusicXMLRepeatDirective(
                            partID: state.currentPartID,
                            measureNumber: state.currentMeasureNumber,
                            direction: direction
                        )
                    )
                }
            case "ending":
                if state.isInBarline,
                   let number = attributeDict["number"],
                   let rawType = attributeDict["type"],
                   let type = MusicXMLEndingType(rawValue: rawType)
                {
                    state.endingDirectives.append(
                        MusicXMLEndingDirective(
                            partID: state.currentPartID,
                            measureNumber: state.currentMeasureNumber,
                            number: number,
                            type: type
                        )
                    )
                }
            case "metronome":
                if state.isInDirection {
                    state.isInDirectionTypeMetronome = true
                    state.metronomeBeatUnit = nil
                    state.metronomeHasDot = false
                    state.metronomePerMinute = nil
                }
            case "sound":
                state.isInSound = true
                state.currentSoundMeasureStartTick = state.currentMeasureStartTick
                state.currentSoundBaseTick = state.partTick[state.currentPartID] ?? state.currentMeasureStartTick
                state.currentSoundTempoStartIndex = state.rawTempoEventsByPart[state.currentPartID]?.count ?? 0
                state.currentSoundSoundStartIndex = state.soundDirectives.count
                state.currentSoundPedalStartIndex = state.pedalEvents.count
                if let tempoText = attributeDict["tempo"], let bpm = Double(tempoText) {
                    recordTempoEvent(quarterBPM: bpm, source: .sound)
                }
                recordDamperPedalEventFromSound(attributes: attributeDict)
                recordSoundDynamicsAttributeIfPresent(attributes: attributeDict)
                if state.isInDirection {
                    recordSoundDirective(attributes: attributeDict)
                }
            case "backup":
                state.isInBackup = true
            case "forward":
                state.isInForward = true
            case "note":
                state.isInNote = true
                state.noteIsRest = false
                state.noteIsChord = false
                state.noteIsGrace = false
                state.noteGraceSlash = false
                state.noteGraceStealTimePrevious = nil
                state.noteGraceStealTimeFollowing = nil
                state.noteStep = nil
                state.noteAlter = nil
                state.noteOctave = nil
                state.noteDuration = nil
                state.noteType = nil
                state.noteDotCount = 0
                state.isInTimeModification = false
                state.noteTimeModificationActualNotes = nil
                state.noteTimeModificationNormalNotes = nil
                state.noteStaff = nil
                state.noteVoice = nil
                state.noteTieStart = false
                state.noteTieStop = false
                state.noteAttackTicks = parseNotePerformanceOffsetTicks(attributeDict["attack"])
                state.noteReleaseTicks = parseNotePerformanceOffsetTicks(attributeDict["release"])
                state.noteDynamicsOverrideVelocity = nil
                state.noteDynamicsOverrideVelocity = parseMIDIVelocity(attributeDict["dynamics"])
                state.isInNoteArticulations = false
                state.noteArticulations = []
                state.noteHasFermata = false
                state.noteArpeggiate = nil
                state.noteFingeringText = nil
                state.notePendingSlurEvents = []
                state.isInTechnical = false
            case "technical":
                if state.isInNote {
                    state.isInTechnical = true
                }
            case "fermata":
                if state.isInNote {
                    state.noteHasFermata = true
                } else if state.isInDirection {
                    recordDirectionFermataEvent()
                }
            case "arpeggiate":
                if state.isInNote {
                    let numberToken = attributeDict["number"].flatMap { token in
                        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
                        return trimmed.isEmpty ? nil : trimmed
                    }
                    let directionToken = attributeDict["direction"].flatMap { token in
                        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
                        return trimmed.isEmpty ? nil : trimmed
                    }
                    state.noteArpeggiate = MusicXMLArpeggiate(numberToken: numberToken, directionToken: directionToken)
                }
            case "grace":
                if state.isInNote {
                    state.noteIsGrace = true
                    let slash = attributeDict["slash"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    state.noteGraceSlash = slash == "yes" || slash == "true" || slash == "1"
                    state.noteGraceStealTimePrevious = parseGraceStealFraction(attributeDict["steal-time-previous"])
                    state.noteGraceStealTimeFollowing = parseGraceStealFraction(attributeDict["steal-time-following"])
                }
            case "dot":
                if state.isInNote {
                    state.noteDotCount += 1
                }
            case "time-modification":
                if state.isInNote {
                    state.isInTimeModification = true
                    state.noteTimeModificationActualNotes = nil
                    state.noteTimeModificationNormalNotes = nil
                }
            case "rest":
                if state.isInNote {
                    state.noteIsRest = true
                }
            case "chord":
                if state.isInNote {
                    state.noteIsChord = true
                }
            case "tie", "tied":
                if state.isInNote {
                    let type = attributeDict["type"]?.lowercased()
                    if type == "start" {
                        state.noteTieStart = true
                    } else if type == "stop" {
                        state.noteTieStop = true
                    }
                }
            case "articulations":
                if state.isInNote {
                    state.isInNoteArticulations = true
                }
            case "slur":
                if state.isInNote {
                    let kind: MusicXMLSlurEventKind? = switch attributeDict["type"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                        case "start":
                            .start
                        case "stop":
                            .stop
                        default:
                            nil
                    }
                    if let kind {
                        let numberToken = attributeDict["number"].flatMap { token in
                            let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
                            return trimmed.isEmpty ? nil : trimmed
                        }
                        state.notePendingSlurEvents.append((kind: kind, numberToken: numberToken))
                    }
                }
            default:
                recordDirectionDynamicsMarkIfPresent(elementName: elementName)
                if state.isInNoteArticulations {
                    let rawName = elementName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    if let articulation = MusicXMLArticulation(rawValue: rawName) {
                        state.noteArticulations.insert(articulation)
                    }
                }
                break
        }
    }

    func handleEndElement(_ elementName: String, text: String) {
        switch elementName {
            case "divisions" where state.isInAttributes:
                if let value = Int(text), value > 0 {
                    state.partDivisions[state.currentPartID] = value
                }
            case "beats" where state.isInTime:
                state.timeBeats = Int(text)
            case "beat-type" where state.isInTime:
                state.timeBeatType = Int(text)
            case "time" where state.isInTime:
                if let beats = state.timeBeats, let beatType = state.timeBeatType, beats > 0, beatType > 0 {
                    let tick = state.partTick[state.currentPartID] ?? state.currentMeasureStartTick
                    state.timeSignatureEvents.append(
                        MusicXMLTimeSignatureEvent(
                            tick: tick,
                            beats: beats,
                            beatType: beatType,
                            scope: MusicXMLEventScope(partID: state.currentPartID, staff: nil, voice: nil)
                        )
                    )
                }
                state.isInTime = false
            case "fifths" where state.isInKey:
                state.keyFifths = Int(text)
            case "mode" where state.isInKey:
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                state.keyModeToken = trimmed.isEmpty ? nil : trimmed
            case "key" where state.isInKey:
                if let fifths = state.keyFifths {
                    let tick = state.partTick[state.currentPartID] ?? state.currentMeasureStartTick
                    state.keySignatureEvents.append(
                        MusicXMLKeySignatureEvent(
                            tick: tick,
                            fifths: fifths,
                            modeToken: state.keyModeToken,
                            scope: MusicXMLEventScope(partID: state.currentPartID, staff: nil, voice: nil)
                        )
                    )
                }
                state.isInKey = false
            case "sign" where state.isInClef:
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                state.clefSignToken = trimmed.isEmpty ? nil : trimmed
            case "line" where state.isInClef:
                state.clefLine = Int(text)
            case "clef-octave-change" where state.isInClef:
                state.clefOctaveChange = Int(text)
            case "clef" where state.isInClef:
                if state.clefSignToken != nil {
                    let tick = state.partTick[state.currentPartID] ?? state.currentMeasureStartTick
                    let numberToken = state.clefNumberToken?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let staff = numberToken.flatMap(Int.init)
                    state.clefEvents.append(
                        MusicXMLClefEvent(
                            tick: tick,
                            signToken: state.clefSignToken,
                            line: state.clefLine,
                            octaveChange: state.clefOctaveChange,
                            numberToken: numberToken?.isEmpty == true ? nil : numberToken,
                            scope: MusicXMLEventScope(partID: state.currentPartID, staff: staff, voice: nil)
                        )
                    )
                }
                state.isInClef = false
            case "beat-unit" where state.isInDirectionTypeMetronome:
                state.metronomeBeatUnit = text
            case "beat-unit-dot" where state.isInDirectionTypeMetronome:
                state.metronomeHasDot = true
            case "per-minute" where state.isInDirectionTypeMetronome:
                state.metronomePerMinute = Double(text)
            case "metronome":
                finalizeMetronomeTempoIfNeeded()
                state.isInDirectionTypeMetronome = false
            case "dynamics":
                state.isInDirectionTypeDynamics = false
            case "offset":
                if let rawOffset = Int(text) {
                    if state.isInSound {
                        applySoundOffset(rawOffset)
                    } else if state.isInDirection, state.currentOffsetAppliesToSound {
                        applyDirectionOffset(rawOffset)
                    }
                }
                state.currentOffsetAppliesToSound = false
            case "technical" where state.isInNote:
                state.isInTechnical = false
            case "fingering" where state.isInNote && state.isInTechnical:
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                state.noteFingeringText = trimmed.isEmpty ? nil : trimmed
            case "duration":
                if let duration = Int(text), duration >= 0 {
                    let normalizedDuration = normalizeDuration(duration)
                    if state.isInNote {
                        state.noteDuration = normalizedDuration
                    } else if state.isInBackup {
                        moveCurrentTick(by: -normalizedDuration)
                    } else if state.isInForward {
                        moveCurrentTick(by: normalizedDuration)
                    }
                }
            case "type" where state.isInNote:
                state.noteType = text
            case "actual-notes" where state.isInNote && state.isInTimeModification:
                state.noteTimeModificationActualNotes = Int(text)
            case "normal-notes" where state.isInNote && state.isInTimeModification:
                state.noteTimeModificationNormalNotes = Int(text)
            case "time-modification":
                if state.isInNote {
                    state.isInTimeModification = false
                }
            case "articulations":
                if state.isInNote {
                    state.isInNoteArticulations = false
                }
            case "step" where state.isInNote:
                state.noteStep = text
            case "alter" where state.isInNote:
                state.noteAlter = Int(text)
            case "octave" where state.isInNote:
                state.noteOctave = Int(text)
            case "staff" where state.isInNote:
                state.noteStaff = Int(text)
            case "staff" where state.isInDirection:
                state.currentDirectionStaff = Int(text)
                if let staff = state.currentDirectionStaff,
                   state.currentDirectionDynamicStartIndex < state.dynamicEvents.count
                {
                    for i in state.currentDirectionDynamicStartIndex ..< state.dynamicEvents.count
                        where state.dynamicEvents[i].scope.staff == nil
                    {
                        state.dynamicEvents[i] = MusicXMLDynamicEvent(
                            tick: state.dynamicEvents[i].tick,
                            velocity: state.dynamicEvents[i].velocity,
                            scope: MusicXMLEventScope(
                                partID: state.dynamicEvents[i].scope.partID,
                                staff: staff,
                                voice: state.dynamicEvents[i].scope.voice
                            ),
                            source: state.dynamicEvents[i].source
                        )
                    }
                }
                if let staff = state.currentDirectionStaff,
                   state.currentDirectionWedgeStartIndex < state.wedgeEvents.count
                {
                    for i in state.currentDirectionWedgeStartIndex ..< state.wedgeEvents.count
                        where state.wedgeEvents[i].scope.staff == nil
                    {
                        state.wedgeEvents[i] = MusicXMLWedgeEvent(
                            tick: state.wedgeEvents[i].tick,
                            kind: state.wedgeEvents[i].kind,
                            numberToken: state.wedgeEvents[i].numberToken,
                            scope: MusicXMLEventScope(
                                partID: state.wedgeEvents[i].scope.partID,
                                staff: staff,
                                voice: state.wedgeEvents[i].scope.voice
                            )
                        )
                    }
                }
                if let staff = state.currentDirectionStaff,
                   state.currentDirectionFermataStartIndex < state.fermataEvents.count
                {
                    for i in state.currentDirectionFermataStartIndex ..< state.fermataEvents.count
                        where state.fermataEvents[i].scope.staff == nil
                    {
                        state.fermataEvents[i] = MusicXMLFermataEvent(
                            tick: state.fermataEvents[i].tick,
                            scope: MusicXMLEventScope(
                                partID: state.fermataEvents[i].scope.partID,
                                staff: staff,
                                voice: state.fermataEvents[i].scope.voice
                            ),
                            source: state.fermataEvents[i].source
                        )
                    }
                }
            case "voice" where state.isInNote:
                state.noteVoice = Int(text)
            case "note":
                finalizeNote()
                state.isInNote = false
                state.isInTechnical = false
            case "attributes":
                state.isInAttributes = false
                state.isInTime = false
                state.isInKey = false
                state.isInClef = false
            case "direction":
                state.isInDirection = false
                state.currentDirectionOffsetTicks = 0
                state.currentDirectionMeasureStartTick = 0
                state.currentDirectionTempoStartIndex = 0
                state.currentDirectionSoundStartIndex = 0
                state.currentDirectionPedalStartIndex = 0
                state.currentDirectionDynamicStartIndex = 0
                state.currentDirectionWedgeStartIndex = 0
                state.currentDirectionFermataStartIndex = 0
                state.currentDirectionSoundOffsetTempoOverrideTicksByIndex = [:]
                state.currentDirectionSoundOffsetSoundOverrideTicksByIndex = [:]
                state.currentDirectionSoundOffsetPedalOverrideTicksByIndex = [:]
                state.currentDirectionStaff = nil
                state.isInDirectionTypeDynamics = false
            case "sound":
                state.isInSound = false
                state.currentSoundBaseTick = 0
                state.currentSoundMeasureStartTick = 0
                state.currentSoundTempoStartIndex = 0
                state.currentSoundSoundStartIndex = 0
                state.currentSoundPedalStartIndex = 0
            case "barline":
                state.isInBarline = false
            case "backup":
                state.isInBackup = false
            case "forward":
                state.isInForward = false
            case "measure":
                let endTick = state.partMeasureMaxTick[state.currentPartID] ?? state.currentMeasureStartTick
                state.measures.append(
                    MusicXMLMeasureSpan(
                        partID: state.currentPartID,
                        measureNumber: state.currentMeasureNumber,
                        measureIndex: state.currentMeasureIndex,
                        measureNumberToken: state.currentMeasureNumberToken,
                        startTick: state.currentMeasureStartTick,
                        endTick: endTick
                    )
                )
                state.partTick[state.currentPartID] = max(endTick, state.partTick[state.currentPartID] ?? 0)
            default:
                break
        }
    }
}
