import Foundation

extension MusicXMLParserDelegate {
    func parseMusicXMLDynamicsVelocity(_ raw: String?) -> UInt8? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.isEmpty == false,
              let percent = Double(raw),
              percent.isFinite
        else {
            return nil
        }
        let velocity = (percent * 90 / 100).rounded(.toNearestOrAwayFromZero)
        return UInt8(min(127, max(0, Int(velocity))))
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
        staff: Int?,
        markToken: String? = nil
    ) {
        state.dynamicEvents.append(
            MusicXMLDynamicEvent(
                sourceID: state.currentSoundSourceID ?? state.currentDirectionSourceID,
                tick: tick,
                velocity: velocity,
                scope: MusicXMLEventScope(partID: state.currentPartID, staff: staff, voice: nil),
                source: source,
                markToken: markToken,
                placementToken: state.isInDirection ? state.currentDirectionPlacementToken : nil
            )
        )
    }

    func recordSoundDynamicsAttributeIfPresent(attributes: [String: String]) {
        guard let velocity = parseMusicXMLDynamicsVelocity(attributes["dynamics"]) else { return }

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
            staff: state.currentDirectionStaff,
            markToken: elementName.lowercased()
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
                sourceID: state.currentDirectionSourceID,
                tick: currentDirectionEventTick(),
                kind: kind,
                numberToken: numberToken,
                scope: MusicXMLEventScope(partID: state.currentPartID, staff: state.currentDirectionStaff, voice: nil)
            )
        )
    }

    func recordOctaveShiftEvent(attributes: [String: String]) {
        guard state.isInDirection,
              let rawType = attributes["type"]?.lowercased(),
              let kind = MusicXMLOctaveShiftKind(rawValue: rawType)
        else { return }
        let size = max(1, Int(attributes["size"] ?? "8") ?? 8)
        let numberToken = attributes["number"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        state.octaveShiftEvents.append(
            MusicXMLOctaveShiftEvent(
                sourceID: state.currentDirectionSourceID,
                tick: currentDirectionEventTick(),
                kind: kind,
                size: size,
                numberToken: numberToken?.isEmpty == true ? nil : numberToken,
                scope: MusicXMLEventScope(
                    partID: state.currentPartID,
                    staff: state.currentDirectionStaff,
                    voice: nil
                )
            )
        )
    }

    func recordDirectionFermataEvent() {
        guard state.isInDirection else { return }
        state.fermataEvents.append(
            MusicXMLFermataEvent(
                sourceID: state.currentDirectionSourceID,
                tick: currentDirectionEventTick(),
                scope: MusicXMLEventScope(partID: state.currentPartID, staff: state.currentDirectionStaff, voice: nil),
                source: .directionType,
                placementToken: state.currentDirectionPlacementToken
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

    func recordPedalEventsFromSound(attributes: [String: String]) {
        let tick: Int = if state.isInDirection {
            currentDirectionEventTick()
        } else {
            state.partTick[state.currentPartID] ?? state.currentMeasureStartTick
        }
        let timeOnlyPasses = parseTimeOnlyPasses(attributes: attributes)

        let pedalAttributes: [(name: String, controller: MusicXMLPedalController)] = [
            ("damper-pedal", .damper),
            ("sostenuto-pedal", .sostenuto),
            ("soft-pedal", .soft),
        ]
        for attribute in pedalAttributes {
            guard let rawValue = attributes[attribute.name],
                  let value = MusicXMLControllerValue(musicXMLString: rawValue)
            else { continue }
            let kind: MusicXMLPedalEventKind = switch value.midiValue {
            case 0: .stop
            case 127: .start
            default: .change
            }
            state.pedalEvents.append(MusicXMLPedalEvent(
                sourceID: state.currentSoundSourceID,
                partID: state.currentPartID,
                measureNumber: state.currentMeasureNumber,
                tick: tick,
                kind: kind,
                controller: attribute.controller,
                value: value,
                timeOnlyPasses: timeOnlyPasses,
                staff: state.isInDirection ? state.currentDirectionStaff : nil,
                placementToken: state.isInDirection ? state.currentDirectionPlacementToken : nil
            ))
        }
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
                    sourceID: state.currentDirectionSourceID,
                    partID: base.partID,
                    measureNumber: base.measureNumber,
                    tick: base.tick,
                    kind: .start,
                    value: .on,
                    timeOnlyPasses: timeOnlyPasses,
                    staff: state.currentDirectionStaff,
                    placementToken: state.currentDirectionPlacementToken
                )
            )
        case "stop":
            state.pedalEvents.append(
                MusicXMLPedalEvent(
                    sourceID: state.currentDirectionSourceID,
                    partID: base.partID,
                    measureNumber: base.measureNumber,
                    tick: base.tick,
                    kind: .stop,
                    value: .off,
                    timeOnlyPasses: timeOnlyPasses,
                    staff: state.currentDirectionStaff,
                    placementToken: state.currentDirectionPlacementToken
                )
            )
        case "change":
            state.pedalEvents.append(
                MusicXMLPedalEvent(
                    sourceID: state.currentDirectionSourceID,
                    partID: base.partID,
                    measureNumber: base.measureNumber,
                    tick: base.tick,
                    kind: .change,
                    value: .off,
                    timeOnlyPasses: timeOnlyPasses,
                    staff: state.currentDirectionStaff,
                    placementToken: state.currentDirectionPlacementToken
                )
            )
            state.pedalEvents.append(
                MusicXMLPedalEvent(
                    sourceID: state.currentDirectionSourceID,
                    partID: base.partID,
                    measureNumber: base.measureNumber,
                    tick: base.tick,
                    kind: .change,
                    value: .on,
                    timeOnlyPasses: timeOnlyPasses,
                    staff: state.currentDirectionStaff,
                    placementToken: state.currentDirectionPlacementToken
                )
            )
        case "continue":
            state.pedalEvents.append(
                MusicXMLPedalEvent(
                    sourceID: state.currentDirectionSourceID,
                    partID: base.partID,
                    measureNumber: base.measureNumber,
                    tick: base.tick,
                    kind: .continue,
                    value: nil,
                    timeOnlyPasses: timeOnlyPasses,
                    staff: state.currentDirectionStaff,
                    placementToken: state.currentDirectionPlacementToken
                )
            )
        default:
            break
        }
    }

    func applyDirectionOffset(_ rawOffset: Double) {
        let newOffset = state.directionOffsetResolver.offsetTicks(
            rawDivisions: rawOffset,
            divisions: state.partDivisions[state.currentPartID]
        ) ?? 0
        let delta = newOffset - state.currentDirectionOffsetTicks
        guard delta != 0, let sourceID = state.currentDirectionSourceID else { return }

        if var tempoEvents = state.rawTempoEventsByPart[state.currentPartID] {
            for i in tempoEvents.indices where tempoEvents[i].sourceID == sourceID {
                let shifted = max(0, tempoEvents[i].tick + delta)
                tempoEvents[i] = RawTempoEvent(
                    sourceID: tempoEvents[i].sourceID,
                    partID: tempoEvents[i].partID,
                    tick: shifted,
                    quarterBPM: tempoEvents[i].quarterBPM,
                    source: tempoEvents[i].source,
                    staff: tempoEvents[i].staff,
                    placementToken: tempoEvents[i].placementToken
                )
            }
            state.rawTempoEventsByPart[state.currentPartID] = tempoEvents
        }

        for i in state.soundDirectives.indices where state.soundDirectives[i].sourceID == sourceID {
            let shifted = max(0, state.soundDirectives[i].tick + delta)
            state.soundDirectives[i] = MusicXMLSoundDirective(
                sourceID: state.soundDirectives[i].sourceID,
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

        for i in state.pedalEvents.indices where state.pedalEvents[i].sourceID == sourceID {
            let shifted = max(0, state.pedalEvents[i].tick + delta)
            state.pedalEvents[i] = MusicXMLPedalEvent(
                sourceID: state.pedalEvents[i].sourceID,
                partID: state.pedalEvents[i].partID,
                measureNumber: state.pedalEvents[i].measureNumber,
                tick: shifted,
                kind: state.pedalEvents[i].kind,
                controller: state.pedalEvents[i].controller,
                value: state.pedalEvents[i].value,
                timeOnlyPasses: state.pedalEvents[i].timeOnlyPasses,
                staff: state.pedalEvents[i].staff,
                placementToken: state.pedalEvents[i].placementToken
            )
        }

        for index in state.dynamicEvents.indices where state.dynamicEvents[index].sourceID == sourceID {
            let event = state.dynamicEvents[index]
            state.dynamicEvents[index] = MusicXMLDynamicEvent(
                sourceID: event.sourceID,
                tick: state.directionOffsetResolver.absoluteTick(
                    directionStartTick: event.tick,
                    offsetTicks: delta
                ),
                velocity: event.velocity,
                scope: event.scope,
                source: event.source,
                markToken: event.markToken,
                placementToken: event.placementToken
            )
        }

        for index in state.wedgeEvents.indices where state.wedgeEvents[index].sourceID == sourceID {
            let event = state.wedgeEvents[index]
            state.wedgeEvents[index] = MusicXMLWedgeEvent(
                sourceID: event.sourceID,
                tick: state.directionOffsetResolver.absoluteTick(
                    directionStartTick: event.tick,
                    offsetTicks: delta
                ),
                kind: event.kind,
                numberToken: event.numberToken,
                scope: event.scope
            )
        }

        for index in state.fermataEvents.indices where state.fermataEvents[index].sourceID == sourceID {
            let event = state.fermataEvents[index]
            state.fermataEvents[index] = MusicXMLFermataEvent(
                sourceID: event.sourceID,
                tick: state.directionOffsetResolver.absoluteTick(
                    directionStartTick: event.tick,
                    offsetTicks: delta
                ),
                scope: event.scope,
                source: event.source,
                placementToken: event.placementToken
            )
        }

        for index in state.wordsEvents.indices where state.wordsEvents[index].sourceID == sourceID {
            let event = state.wordsEvents[index]
            state.wordsEvents[index] = MusicXMLWordsEvent(
                sourceID: event.sourceID,
                tick: state.directionOffsetResolver.absoluteTick(
                    directionStartTick: event.tick,
                    offsetTicks: delta
                ),
                text: event.text,
                scope: event.scope,
                placementToken: event.placementToken
            )
        }

        for index in state.octaveShiftEvents.indices
            where state.octaveShiftEvents[index].sourceID == sourceID
        {
            let event = state.octaveShiftEvents[index]
            state.octaveShiftEvents[index] = MusicXMLOctaveShiftEvent(
                sourceID: event.sourceID,
                tick: state.directionOffsetResolver.absoluteTick(
                    directionStartTick: event.tick,
                    offsetTicks: delta
                ),
                kind: event.kind,
                size: event.size,
                numberToken: event.numberToken,
                scope: event.scope
            )
        }

        state.currentDirectionOffsetTicks = newOffset
    }

    func applySoundOffset(_ rawOffset: Double) {
        let offsetTicks = state.directionOffsetResolver.offsetTicks(
            rawDivisions: rawOffset,
            divisions: state.partDivisions[state.currentPartID]
        ) ?? 0
        let tick = state.directionOffsetResolver.absoluteTick(
            directionStartTick: state.currentSoundBaseTick,
            offsetTicks: offsetTicks
        )

        if var tempoEvents = state.rawTempoEventsByPart[state.currentPartID],
           state.currentSoundEventStartIndices.tempo < tempoEvents.count
        {
            for i in state.currentSoundEventStartIndices.tempo ..< tempoEvents.count {
                tempoEvents[i] = RawTempoEvent(
                    sourceID: tempoEvents[i].sourceID,
                    partID: tempoEvents[i].partID,
                    tick: tick,
                    quarterBPM: tempoEvents[i].quarterBPM,
                    source: tempoEvents[i].source,
                    staff: tempoEvents[i].staff,
                    placementToken: tempoEvents[i].placementToken
                )
            }
            state.rawTempoEventsByPart[state.currentPartID] = tempoEvents
        }

        if state.currentSoundEventStartIndices.sound < state.soundDirectives.count {
            for i in state.currentSoundEventStartIndices.sound ..< state.soundDirectives.count {
                state.soundDirectives[i] = MusicXMLSoundDirective(
                    sourceID: state.soundDirectives[i].sourceID,
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
            }
        }

        if state.currentSoundEventStartIndices.pedal < state.pedalEvents.count {
            for i in state.currentSoundEventStartIndices.pedal ..< state.pedalEvents.count {
                state.pedalEvents[i] = MusicXMLPedalEvent(
                    sourceID: state.pedalEvents[i].sourceID,
                    partID: state.pedalEvents[i].partID,
                    measureNumber: state.pedalEvents[i].measureNumber,
                    tick: tick,
                    kind: state.pedalEvents[i].kind,
                    controller: state.pedalEvents[i].controller,
                    value: state.pedalEvents[i].value,
                    timeOnlyPasses: state.pedalEvents[i].timeOnlyPasses,
                    staff: state.pedalEvents[i].staff,
                    placementToken: state.pedalEvents[i].placementToken
                )
            }
        }
    }

    func nextDirectionSourceID() -> MusicXMLDirectionSourceID {
        defer { state.currentDirectionSourceOrdinal += 1 }
        return MusicXMLDirectionSourceID(
            partID: state.currentPartID,
            sourceMeasureIndex: state.currentMeasureIndex,
            sourceMeasureNumberToken: state.currentMeasureNumberToken,
            sourceOrdinal: state.currentDirectionSourceOrdinal
        )
    }

    func currentDirectionEventTick() -> Int {
        let baseTick = state.partTick[state.currentPartID] ?? state.currentMeasureStartTick
        guard state.isInDirection else { return baseTick }
        return state.directionOffsetResolver.absoluteTick(
            directionStartTick: baseTick,
            offsetTicks: state.currentDirectionOffsetTicks
        )
    }

    func recordTempoEvent(quarterBPM: Double, source: TempoSource) {
        guard quarterBPM.isFinite, quarterBPM > 0 else { return }

        let tick = currentDirectionEventTick()
        let event = RawTempoEvent(
            sourceID: state.currentSoundSourceID ?? state.currentDirectionSourceID,
            partID: state.currentPartID,
            tick: tick,
            quarterBPM: quarterBPM,
            source: source,
            staff: state.currentDirectionStaff,
            placementToken: state.isInDirection ? state.currentDirectionPlacementToken : nil
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
                sourceID: state.currentSoundSourceID,
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
                    sourceID: $0.sourceID,
                    tick: $0.tick,
                    quarterBPM: $0.quarterBPM,
                    scope: MusicXMLEventScope(partID: $0.partID, staff: $0.staff, voice: nil),
                    placementToken: $0.placementToken
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
