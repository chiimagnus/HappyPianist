import Foundation

extension MusicXMLParserDelegate {
    func parseMIDIVelocity(_ raw: String?) -> UInt8? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.isEmpty == false,
              let value = Int(raw)
        else {
            return nil
        }
        let clamped = min(127, max(0, value))
        return UInt8(clamped)
    }

    func velocityForDynamicsMark(_ markElementName: String) -> UInt8? {
        switch markElementName.lowercased() {
            case "ppp":
                30
            case "pp":
                40
            case "p":
                50
            case "mp":
                60
            case "mf":
                75
            case "f":
                90
            case "ff":
                105
            case "fff":
                115
            case "ffff":
                120
            default:
                nil
        }
    }

    func recordDynamicEvent(
        tick: Int,
        velocity: UInt8,
        source: MusicXMLDynamicEventSource,
        staff: Int?
    ) {
        state.dynamicEvents.append(
            MusicXMLDynamicEvent(
                tick: tick,
                velocity: velocity,
                scope: MusicXMLEventScope(partID: state.currentPartID, staff: staff, voice: nil),
                source: source
            )
        )
    }

    func recordSoundDynamicsAttributeIfPresent(attributes: [String: String]) {
        guard let velocity = parseMIDIVelocity(attributes["dynamics"]) else { return }

        let tick: Int = if state.isInDirection {
            currentDirectionEventTick()
        } else {
            state.partTick[state.currentPartID] ?? state.currentMeasureStartTick
        }

        recordDynamicEvent(
            tick: tick,
            velocity: velocity,
            source: .soundDynamicsAttribute,
            staff: state.isInDirection ? state.currentDirectionStaff : nil
        )
    }

    func recordDirectionDynamicsMarkIfPresent(elementName: String) {
        guard state.isInDirectionTypeDynamics else { return }
        guard let velocity = velocityForDynamicsMark(elementName) else { return }
        recordDynamicEvent(
            tick: currentDirectionEventTick(),
            velocity: velocity,
            source: .directionDynamics,
            staff: state.currentDirectionStaff
        )
    }

    func recordWedgeEvent(attributes: [String: String]) {
        guard state.isInDirection else { return }
        guard let rawType = attributes["type"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              rawType.isEmpty == false
        else {
            return
        }

        let kind: MusicXMLWedgeKind? = switch rawType.lowercased() {
            case "crescendo":
                .crescendoStart
            case "diminuendo":
                .diminuendoStart
            case "stop":
                .stop
            default:
                nil
        }

        guard let kind else { return }

        let numberToken = attributes["number"].flatMap { token in
            let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        state.wedgeEvents.append(
            MusicXMLWedgeEvent(
                tick: currentDirectionEventTick(),
                kind: kind,
                numberToken: numberToken,
                scope: MusicXMLEventScope(partID: state.currentPartID, staff: state.currentDirectionStaff, voice: nil)
            )
        )
    }

    func recordDirectionFermataEvent() {
        guard state.isInDirection else { return }
        state.fermataEvents.append(
            MusicXMLFermataEvent(
                tick: currentDirectionEventTick(),
                scope: MusicXMLEventScope(partID: state.currentPartID, staff: state.currentDirectionStaff, voice: nil),
                source: .directionType
            )
        )
    }

    func parseTimeOnlyPasses(attributes: [String: String]) -> [Int]? {
        guard let raw = attributes["time-only"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.isEmpty == false
        else {
            return nil
        }

        let passes = raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .compactMap(Int.init)
            .filter { $0 > 0 }

        guard passes.isEmpty == false else { return nil }

        var unique = Array(Set(passes))
        unique.sort()
        return unique
    }

    func recordDamperPedalEventFromSound(attributes: [String: String]) {
        guard let rawValue = attributes["damper-pedal"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              rawValue.isEmpty == false
        else {
            return
        }

        let lowered = rawValue.lowercased()
        let isDown: Bool? = switch lowered {
            case "yes":
                true
            case "no":
                false
            default:
                if let value = Int(lowered) {
                    value > 0
                } else {
                    nil
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

        let timeOnlyPasses = parseTimeOnlyPasses(attributes: attributes)
        state.pedalEvents.append(
            MusicXMLPedalEvent(
                partID: state.currentPartID,
                measureNumber: state.currentMeasureNumber,
                tick: tick,
                kind: isDown ? .start : .stop,
                isDown: isDown,
                timeOnlyPasses: timeOnlyPasses
            )
        )
    }

    func recordPedalEvent(attributes: [String: String]) {
        guard state.isInDirection else { return }

        guard let rawType = attributes["type"]?.lowercased() else { return }

        let tick = currentDirectionEventTick()
        let timeOnlyPasses = parseTimeOnlyPasses(attributes: attributes)
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
                        isDown: true,
                        timeOnlyPasses: timeOnlyPasses
                    )
                )
            case "stop":
                state.pedalEvents.append(
                    MusicXMLPedalEvent(
                        partID: base.partID,
                        measureNumber: base.measureNumber,
                        tick: base.tick,
                        kind: .stop,
                        isDown: false,
                        timeOnlyPasses: timeOnlyPasses
                    )
                )
            case "change":
                state.pedalEvents.append(
                    MusicXMLPedalEvent(
                        partID: base.partID,
                        measureNumber: base.measureNumber,
                        tick: base.tick,
                        kind: .change,
                        isDown: false,
                        timeOnlyPasses: timeOnlyPasses
                    )
                )
                state.pedalEvents.append(
                    MusicXMLPedalEvent(
                        partID: base.partID,
                        measureNumber: base.measureNumber,
                        tick: base.tick,
                        kind: .change,
                        isDown: true,
                        timeOnlyPasses: timeOnlyPasses
                    )
                )
            case "continue":
                state.pedalEvents.append(
                    MusicXMLPedalEvent(
                        partID: base.partID,
                        measureNumber: base.measureNumber,
                        tick: base.tick,
                        kind: .continue,
                        isDown: nil,
                        timeOnlyPasses: timeOnlyPasses
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
                    source: tempoEvents[i].source,
                    staff: tempoEvents[i].staff
                )
            }
            if state.currentDirectionSoundOffsetTempoOverrideTicksByIndex.isEmpty == false {
                for (i, overrideTick) in state.currentDirectionSoundOffsetTempoOverrideTicksByIndex
                    where i >= state.currentDirectionTempoStartIndex && i < tempoEvents.count
                {
                    tempoEvents[i] = RawTempoEvent(
                        partID: tempoEvents[i].partID,
                        tick: overrideTick,
                        quarterBPM: tempoEvents[i].quarterBPM,
                        source: tempoEvents[i].source,
                        staff: tempoEvents[i].staff
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
                    dacapo: state.soundDirectives[i].dacapo,
                    timeOnlyPasses: state.soundDirectives[i].timeOnlyPasses
                )
            }
            if state.currentDirectionSoundOffsetSoundOverrideTicksByIndex.isEmpty == false {
                for (i, overrideTick) in state.currentDirectionSoundOffsetSoundOverrideTicksByIndex
                    where i >= state.currentDirectionSoundStartIndex && i < state.soundDirectives.count
                {
                    state.soundDirectives[i] = MusicXMLSoundDirective(
                        partID: state.soundDirectives[i].partID,
                        measureNumber: state.soundDirectives[i].measureNumber,
                        tick: overrideTick,
                        segno: state.soundDirectives[i].segno,
                        coda: state.soundDirectives[i].coda,
                        tocoda: state.soundDirectives[i].tocoda,
                        dalsegno: state.soundDirectives[i].dalsegno,
                        dacapo: state.soundDirectives[i].dacapo,
                        timeOnlyPasses: state.soundDirectives[i].timeOnlyPasses
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
                    isDown: state.pedalEvents[i].isDown,
                    timeOnlyPasses: state.pedalEvents[i].timeOnlyPasses
                )
            }
            if state.currentDirectionSoundOffsetPedalOverrideTicksByIndex.isEmpty == false {
                for (i, overrideTick) in state.currentDirectionSoundOffsetPedalOverrideTicksByIndex
                    where i >= state.currentDirectionPedalStartIndex && i < state.pedalEvents.count
                {
                    state.pedalEvents[i] = MusicXMLPedalEvent(
                        partID: state.pedalEvents[i].partID,
                        measureNumber: state.pedalEvents[i].measureNumber,
                        tick: overrideTick,
                        kind: state.pedalEvents[i].kind,
                        isDown: state.pedalEvents[i].isDown,
                        timeOnlyPasses: state.pedalEvents[i].timeOnlyPasses
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
                    source: tempoEvents[i].source,
                    staff: tempoEvents[i].staff
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
                    dacapo: state.soundDirectives[i].dacapo,
                    timeOnlyPasses: state.soundDirectives[i].timeOnlyPasses
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
                    isDown: state.pedalEvents[i].isDown,
                    timeOnlyPasses: state.pedalEvents[i].timeOnlyPasses
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
        let event = RawTempoEvent(
            partID: state.currentPartID,
            tick: tick,
            quarterBPM: quarterBPM,
            source: source,
            staff: state.currentDirectionStaff
        )
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
        let timeOnlyPasses = parseTimeOnlyPasses(attributes: attributes)
        state.soundDirectives.append(
            MusicXMLSoundDirective(
                partID: state.currentPartID,
                measureNumber: state.currentMeasureNumber,
                tick: tick,
                segno: segno,
                coda: coda,
                tocoda: tocoda,
                dalsegno: dalsegno,
                dacapo: dacapo,
                timeOnlyPasses: timeOnlyPasses
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

        let beatUnitInQuarters: Double? = switch beatUnit {
            case "whole":
                4
            case "half":
                2
            case "quarter":
                1
            case "eighth":
                0.5
            default:
                nil
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
        guard state.rawTempoEventsByPart.isEmpty == false else { return [] }

        var output: [MusicXMLTempoEvent] = []
        output.reserveCapacity(state.rawTempoEventsByPart.values.reduce(0) { $0 + $1.count })

        for partID in state.rawTempoEventsByPart.keys.sorted() {
            let rawEvents = state.rawTempoEventsByPart[partID] ?? []
            guard rawEvents.isEmpty == false else { continue }

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

            output.append(contentsOf: byTick.values.map {
                MusicXMLTempoEvent(
                    tick: $0.tick,
                    quarterBPM: $0.quarterBPM,
                    scope: MusicXMLEventScope(partID: $0.partID, staff: $0.staff, voice: nil)
                )
            })
        }

        output.sort { lhs, rhs in
            if lhs.scope.partID != rhs.scope.partID { return lhs.scope.partID < rhs.scope.partID }
            return lhs.tick < rhs.tick
        }
        return output
    }
}
