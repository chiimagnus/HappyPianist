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
            case "direction":
                state.isInDirection = true
                state.currentDirectionOffsetTicks = 0
                state.currentDirectionMeasureStartTick = state.currentMeasureStartTick
                state.currentDirectionTempoStartIndex = state.rawTempoEventsByPart[state.currentPartID]?.count ?? 0
                state.currentDirectionSoundStartIndex = state.soundDirectives.count
                state.currentDirectionPedalStartIndex = state.pedalEvents.count
                state.currentDirectionDynamicStartIndex = state.dynamicEvents.count
                state.currentDirectionWedgeStartIndex = state.wedgeEvents.count
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
            case "grace":
                if state.isInNote {
                    state.noteIsGrace = true
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
            case "voice" where state.isInNote:
                state.noteVoice = Int(text)
            case "note":
                finalizeNote()
                state.isInNote = false
            case "attributes":
                state.isInAttributes = false
            case "direction":
                state.isInDirection = false
                state.currentDirectionOffsetTicks = 0
                state.currentDirectionMeasureStartTick = 0
                state.currentDirectionTempoStartIndex = 0
                state.currentDirectionSoundStartIndex = 0
                state.currentDirectionPedalStartIndex = 0
                state.currentDirectionDynamicStartIndex = 0
                state.currentDirectionWedgeStartIndex = 0
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
