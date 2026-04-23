import Foundation

extension MusicXMLParserDelegate {
    func handleStartElement(_ elementName: String, attributes attributeDict: [String: String]) {
        switch elementName {
            case "part":
                state.currentPartID = attributeDict["id"] ?? "P1"
                if state.partDivisions[state.currentPartID] == nil {
                    state.partDivisions[state.currentPartID] = 1
                }
                state.currentMeasureStartTick = state.partTick[state.currentPartID] ?? 0
                state.partMeasureMaxTick[state.currentPartID] = state.currentMeasureStartTick
            case "measure":
                state.currentMeasureNumber = Int(attributeDict["number"] ?? "") ?? (state.currentMeasureNumber + 1)
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
            case "direction-type":
                break
            case "pedal":
                recordPedalEvent(attributes: attributeDict)
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
                if state.isInDirection, let tempoText = attributeDict["tempo"], let bpm = Double(tempoText) {
                    recordTempoEvent(quarterBPM: bpm, source: .sound)
                }
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
                state.noteStep = nil
                state.noteAlter = nil
                state.noteOctave = nil
                state.noteDuration = nil
                state.noteStaff = nil
                state.noteVoice = nil
                state.noteTieStart = false
                state.noteTieStop = false
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
            default:
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
            case "offset" where state.isInDirection:
                if let rawOffset = Int(text) {
                    applyDirectionOffset(rawOffset)
                }
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
            case "step" where state.isInNote:
                state.noteStep = text
            case "alter" where state.isInNote:
                state.noteAlter = Int(text)
            case "octave" where state.isInNote:
                state.noteOctave = Int(text)
            case "staff" where state.isInNote:
                state.noteStaff = Int(text)
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
