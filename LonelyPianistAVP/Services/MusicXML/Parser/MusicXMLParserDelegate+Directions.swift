import Foundation

extension MusicXMLParserDelegate {
    func recordDamperPedalEventFromSound(attributes: [String: String]) {
        guard let rawValue = attributes["damper-pedal"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              rawValue.isEmpty == false
        else {
            return
        }

        let lowered = rawValue.lowercased()
        let isDown: Bool?
        switch lowered {
            case "yes":
                isDown = true
            case "no":
                isDown = false
            default:
                if let value = Int(lowered) {
                    isDown = value > 0
                } else {
                    isDown = nil
                }
        }

        guard let isDown else {
            return
        }

        let tick: Int = if state.isInDirection {
            currentDirectionEventTick()
        } else {
            state.partTick[state.currentPartID] ?? state.currentMeasureStartTick
        }

        state.pedalEvents.append(
            MusicXMLPedalEvent(
                partID: state.currentPartID,
                measureNumber: state.currentMeasureNumber,
                tick: tick,
                kind: isDown ? .start : .stop,
                isDown: isDown
            )
        )
    }

    func recordPedalEvent(attributes: [String: String]) {
        guard state.isInDirection else { return }

        guard let rawType = attributes["type"]?.lowercased() else { return }

        let tick = currentDirectionEventTick()
        let base = (
            partID: state.currentPartID,
            measureNumber: state.currentMeasureNumber,
            tick: tick
        )

        switch rawType {
            case "start":
                state.pedalEvents.append(
                    MusicXMLPedalEvent(
                        partID: base.partID,
                        measureNumber: base.measureNumber,
                        tick: base.tick,
                        kind: .start,
                        isDown: true
                    )
                )
            case "stop":
                state.pedalEvents.append(
                    MusicXMLPedalEvent(
                        partID: base.partID,
                        measureNumber: base.measureNumber,
                        tick: base.tick,
                        kind: .stop,
                        isDown: false
                    )
                )
            case "change":
                state.pedalEvents.append(
                    MusicXMLPedalEvent(
                        partID: base.partID,
                        measureNumber: base.measureNumber,
                        tick: base.tick,
                        kind: .change,
                        isDown: false
                    )
                )
                state.pedalEvents.append(
                    MusicXMLPedalEvent(
                        partID: base.partID,
                        measureNumber: base.measureNumber,
                        tick: base.tick,
                        kind: .change,
                        isDown: true
                    )
                )
            case "continue":
                state.pedalEvents.append(
                    MusicXMLPedalEvent(
                        partID: base.partID,
                        measureNumber: base.measureNumber,
                        tick: base.tick,
                        kind: .continue,
                        isDown: nil
                    )
                )
            default:
                #if DEBUG
                    print(
                        "MusicXMLParser: ignored pedal type '\(rawType)' at \(base.partID) measure \(base.measureNumber) tick \(base.tick)"
                    )
                #endif
        }
    }

    func applyDirectionOffset(_ rawOffset: Int) {
        let newOffset = normalizeSignedDuration(rawOffset)
        let delta = newOffset - state.currentDirectionOffsetTicks
        guard delta != 0 else { return }

        if var tempoEvents = state.rawTempoEventsByPart[state.currentPartID],
           state.currentDirectionTempoStartIndex < tempoEvents.count
        {
            for i in state.currentDirectionTempoStartIndex ..< tempoEvents.count {
                let shifted = max(state.currentDirectionMeasureStartTick, tempoEvents[i].tick + delta)
                tempoEvents[i] = RawTempoEvent(
                    partID: tempoEvents[i].partID,
                    tick: shifted,
                    quarterBPM: tempoEvents[i].quarterBPM,
                    source: tempoEvents[i].source
                )
            }
            if state.currentDirectionSoundOffsetTempoOverrideTicksByIndex.isEmpty == false {
                for (i, overrideTick) in state.currentDirectionSoundOffsetTempoOverrideTicksByIndex
                where i >= state.currentDirectionTempoStartIndex && i < tempoEvents.count {
                    tempoEvents[i] = RawTempoEvent(
                        partID: tempoEvents[i].partID,
                        tick: overrideTick,
                        quarterBPM: tempoEvents[i].quarterBPM,
                        source: tempoEvents[i].source
                    )
                }
            }
            state.rawTempoEventsByPart[state.currentPartID] = tempoEvents
        }

        if state.currentDirectionSoundStartIndex < state.soundDirectives.count {
            for i in state.currentDirectionSoundStartIndex ..< state.soundDirectives.count {
                let shifted = max(state.currentDirectionMeasureStartTick, state.soundDirectives[i].tick + delta)
                state.soundDirectives[i] = MusicXMLSoundDirective(
                    partID: state.soundDirectives[i].partID,
                    measureNumber: state.soundDirectives[i].measureNumber,
                    tick: shifted,
                    segno: state.soundDirectives[i].segno,
                    coda: state.soundDirectives[i].coda,
                    tocoda: state.soundDirectives[i].tocoda,
                    dalsegno: state.soundDirectives[i].dalsegno,
                    dacapo: state.soundDirectives[i].dacapo
                )
            }
            if state.currentDirectionSoundOffsetSoundOverrideTicksByIndex.isEmpty == false {
                for (i, overrideTick) in state.currentDirectionSoundOffsetSoundOverrideTicksByIndex
                where i >= state.currentDirectionSoundStartIndex && i < state.soundDirectives.count {
                    state.soundDirectives[i] = MusicXMLSoundDirective(
                        partID: state.soundDirectives[i].partID,
                        measureNumber: state.soundDirectives[i].measureNumber,
                        tick: overrideTick,
                        segno: state.soundDirectives[i].segno,
                        coda: state.soundDirectives[i].coda,
                        tocoda: state.soundDirectives[i].tocoda,
                        dalsegno: state.soundDirectives[i].dalsegno,
                        dacapo: state.soundDirectives[i].dacapo
                    )
                }
            }
        }

        if state.currentDirectionPedalStartIndex < state.pedalEvents.count {
            for i in state.currentDirectionPedalStartIndex ..< state.pedalEvents.count {
                let shifted = max(state.currentDirectionMeasureStartTick, state.pedalEvents[i].tick + delta)
                state.pedalEvents[i] = MusicXMLPedalEvent(
                    partID: state.pedalEvents[i].partID,
                    measureNumber: state.pedalEvents[i].measureNumber,
                    tick: shifted,
                    kind: state.pedalEvents[i].kind,
                    isDown: state.pedalEvents[i].isDown
                )
            }
            if state.currentDirectionSoundOffsetPedalOverrideTicksByIndex.isEmpty == false {
                for (i, overrideTick) in state.currentDirectionSoundOffsetPedalOverrideTicksByIndex
                where i >= state.currentDirectionPedalStartIndex && i < state.pedalEvents.count {
                    state.pedalEvents[i] = MusicXMLPedalEvent(
                        partID: state.pedalEvents[i].partID,
                        measureNumber: state.pedalEvents[i].measureNumber,
                        tick: overrideTick,
                        kind: state.pedalEvents[i].kind,
                        isDown: state.pedalEvents[i].isDown
                    )
                }
            }
        }

        state.currentDirectionOffsetTicks = newOffset
    }

    func applySoundOffset(_ rawOffset: Int) {
        let offsetTicks = normalizeSignedDuration(rawOffset)
        let tick = max(state.currentSoundMeasureStartTick, state.currentSoundBaseTick + offsetTicks)

        if var tempoEvents = state.rawTempoEventsByPart[state.currentPartID],
           state.currentSoundTempoStartIndex < tempoEvents.count
        {
            for i in state.currentSoundTempoStartIndex ..< tempoEvents.count {
                tempoEvents[i] = RawTempoEvent(
                    partID: tempoEvents[i].partID,
                    tick: tick,
                    quarterBPM: tempoEvents[i].quarterBPM,
                    source: tempoEvents[i].source
                )
                if state.isInDirection {
                    state.currentDirectionSoundOffsetTempoOverrideTicksByIndex[i] = tick
                }
            }
            state.rawTempoEventsByPart[state.currentPartID] = tempoEvents
        }

        if state.currentSoundSoundStartIndex < state.soundDirectives.count {
            for i in state.currentSoundSoundStartIndex ..< state.soundDirectives.count {
                state.soundDirectives[i] = MusicXMLSoundDirective(
                    partID: state.soundDirectives[i].partID,
                    measureNumber: state.soundDirectives[i].measureNumber,
                    tick: tick,
                    segno: state.soundDirectives[i].segno,
                    coda: state.soundDirectives[i].coda,
                    tocoda: state.soundDirectives[i].tocoda,
                    dalsegno: state.soundDirectives[i].dalsegno,
                    dacapo: state.soundDirectives[i].dacapo
                )
                if state.isInDirection {
                    state.currentDirectionSoundOffsetSoundOverrideTicksByIndex[i] = tick
                }
            }
        }

        if state.currentSoundPedalStartIndex < state.pedalEvents.count {
            for i in state.currentSoundPedalStartIndex ..< state.pedalEvents.count {
                state.pedalEvents[i] = MusicXMLPedalEvent(
                    partID: state.pedalEvents[i].partID,
                    measureNumber: state.pedalEvents[i].measureNumber,
                    tick: tick,
                    kind: state.pedalEvents[i].kind,
                    isDown: state.pedalEvents[i].isDown
                )
                if state.isInDirection {
                    state.currentDirectionSoundOffsetPedalOverrideTicksByIndex[i] = tick
                }
            }
        }
    }

    func currentDirectionEventTick() -> Int {
        let baseTick = state.partTick[state.currentPartID] ?? state.currentMeasureStartTick
        guard state.isInDirection else { return baseTick }
        let shifted = baseTick + state.currentDirectionOffsetTicks
        return max(state.currentDirectionMeasureStartTick, shifted)
    }

    func recordTempoEvent(quarterBPM: Double, source: TempoSource) {
        guard quarterBPM.isFinite, quarterBPM > 0 else { return }

        let tick = currentDirectionEventTick()
        let event = RawTempoEvent(partID: state.currentPartID, tick: tick, quarterBPM: quarterBPM, source: source)
        state.rawTempoEventsByPart[state.currentPartID, default: []].append(event)
    }

    func recordSoundDirective(attributes: [String: String]) {
        let segno = attributes["segno"].flatMap { $0.isEmpty ? nil : $0 }
        let coda = attributes["coda"].flatMap { $0.isEmpty ? nil : $0 }
        let tocoda = attributes["tocoda"].flatMap { $0.isEmpty ? nil : $0 }
        let dalsegno = attributes["dalsegno"].flatMap { $0.isEmpty ? nil : $0 }
        let dacapo = attributes["dacapo"].flatMap { $0.isEmpty ? nil : $0 }

        guard segno != nil || coda != nil || tocoda != nil || dalsegno != nil || dacapo != nil else {
            return
        }

        let tick = currentDirectionEventTick()
        state.soundDirectives.append(
            MusicXMLSoundDirective(
                partID: state.currentPartID,
                measureNumber: state.currentMeasureNumber,
                tick: tick,
                segno: segno,
                coda: coda,
                tocoda: tocoda,
                dalsegno: dalsegno,
                dacapo: dacapo
            )
        )
    }

    func finalizeMetronomeTempoIfNeeded() {
        guard let beatUnit = state.metronomeBeatUnit?.lowercased(),
              let perMinute = state.metronomePerMinute,
              perMinute.isFinite,
              perMinute > 0
        else {
            return
        }

        let beatUnitInQuarters: Double?
        switch beatUnit {
            case "whole":
                beatUnitInQuarters = 4
            case "half":
                beatUnitInQuarters = 2
            case "quarter":
                beatUnitInQuarters = 1
            case "eighth":
                beatUnitInQuarters = 0.5
            default:
                beatUnitInQuarters = nil
        }

        guard let beatUnitInQuarters else {
            #if DEBUG
                print("MusicXMLParser: ignoring metronome beatUnit=\(beatUnit)")
            #endif
            return
        }

        let dottedMultiplier = state.metronomeHasDot ? 1.5 : 1.0
        recordTempoEvent(quarterBPM: perMinute * beatUnitInQuarters * dottedMultiplier, source: .metronome)
    }

    func finalizeTempoEvents() -> [MusicXMLTempoEvent] {
        let primaryPart = "P1"
        let rawEvents: [RawTempoEvent] = if let p1Events = state.rawTempoEventsByPart[primaryPart],
                                            p1Events.isEmpty == false
        {
            p1Events
        } else {
            state.rawTempoEventsByPart.keys.sorted().flatMap { partID in
                state.rawTempoEventsByPart[partID] ?? []
            }
        }

        guard rawEvents.isEmpty == false else { return [] }

        var byTick: [Int: RawTempoEvent] = [:]
        for event in rawEvents {
            if let existing = byTick[event.tick] {
                if event.source.rawValue > existing.source.rawValue {
                    byTick[event.tick] = event
                } else if event.source == existing.source {
                    byTick[event.tick] = event
                }
            } else {
                byTick[event.tick] = event
            }
        }

        return byTick.values
            .sorted { $0.tick < $1.tick }
            .map { MusicXMLTempoEvent(tick: $0.tick, quarterBPM: $0.quarterBPM) }
    }
}
