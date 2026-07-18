import Foundation

enum MusicXMLTempoWordKind: String, Equatable, Sendable {
    case ritardando
    case rallentando
    case accelerando
    case stringendo
    case aTempo
    case tempoPrimo
    case doppioMovimento
    case menoMosso
}

enum MusicXMLTempoWordResolution: Equatable, Sendable {
    case tempoRamp
    case tempoEvent
    case explicitEventAtMarker
    case approximation(reason: String)
}

struct MusicXMLTempoWordAnnotation: Equatable, Sendable {
    let sourceID: MusicXMLDirectionSourceID?
    let tick: Int
    let text: String
    let scope: MusicXMLEventScope
    let kind: MusicXMLTempoWordKind
    let resolution: MusicXMLTempoWordResolution
}

struct MusicXMLWordsSemanticsResult: Equatable {
    let derivedTempoEvents: [MusicXMLTempoEvent]
    let derivedTempoRamps: [MusicXMLTempoMap.TempoRamp]
    let derivedPedalEvents: [MusicXMLPedalEvent]
    let tempoAnnotations: [MusicXMLTempoWordAnnotation]
}

struct MusicXMLWordsSemanticsInterpreter {
    func interpret(
        wordsEvents: [MusicXMLWordsEvent],
        tempoEvents: [MusicXMLTempoEvent]
    ) -> MusicXMLWordsSemanticsResult {
        let markers = wordsEvents
            .compactMap(Self.marker(from:))
            .sorted(by: Self.markerOrder)
        let validatedTempoEvents = Self.validatedTempoEvents(tempoEvents)

        let pedalEvents = markers.compactMap(Self.pedalEvent(from:))
        var derivedTempoEvents: [MusicXMLTempoEvent] = []
        var derivedTempoRamps: [MusicXMLTempoMap.TempoRamp] = []
        var annotations: [MusicXMLTempoWordAnnotation] = []

        for (index, marker) in markers.enumerated() {
            guard let tempoKind = marker.kind.tempoKind else { continue }
            let combinedTempoEvents = Self.dedupTempoEvents(validatedTempoEvents + derivedTempoEvents)
            let scope = MusicXMLEventScope(partID: marker.scope.partID, staff: nil, voice: nil)

            switch marker.kind {
            case .ritardando, .rallentando, .menoMosso:
                if let ramp = Self.tempoRampIfPossible(
                    startTick: marker.tick,
                    direction: .slower,
                    explicitTempoEvents: combinedTempoEvents,
                    scope: scope
                ) {
                    derivedTempoRamps.append(ramp)
                    annotations.append(marker.annotation(kind: tempoKind, resolution: .tempoRamp))
                } else {
                    annotations.append(marker.annotation(
                        kind: tempoKind,
                        resolution: .approximation(reason: "tempo-word-missing-slower-explicit-target")
                    ))
                }

            case .accelerando, .stringendo:
                if let ramp = Self.tempoRampIfPossible(
                    startTick: marker.tick,
                    direction: .faster,
                    explicitTempoEvents: combinedTempoEvents,
                    scope: scope
                ) {
                    derivedTempoRamps.append(ramp)
                    annotations.append(marker.annotation(kind: tempoKind, resolution: .tempoRamp))
                } else {
                    annotations.append(marker.annotation(
                        kind: tempoKind,
                        resolution: .approximation(reason: "tempo-word-missing-faster-explicit-target")
                    ))
                }

            case .aTempo:
                if Self.hasExplicitTempo(atTick: marker.tick, tempoEvents: combinedTempoEvents, partID: scope.partID) {
                    annotations.append(marker.annotation(kind: tempoKind, resolution: .explicitEventAtMarker))
                } else if let bpm = Self.aTempoAnchorBPM(
                    markerIndex: index,
                    markers: markers,
                    tempoEvents: combinedTempoEvents,
                    partID: scope.partID
                ) {
                    derivedTempoEvents.append(MusicXMLTempoEvent(
                        sourceID: marker.sourceID,
                        tick: marker.tick,
                        quarterBPM: bpm,
                        scope: scope
                    ))
                    annotations.append(marker.annotation(kind: tempoKind, resolution: .tempoEvent))
                } else {
                    annotations.append(marker.annotation(
                        kind: tempoKind,
                        resolution: .approximation(reason: "a-tempo-missing-prior-anchor")
                    ))
                }

            case .tempoPrimo:
                if Self.hasExplicitTempo(atTick: marker.tick, tempoEvents: combinedTempoEvents, partID: scope.partID) {
                    annotations.append(marker.annotation(kind: tempoKind, resolution: .explicitEventAtMarker))
                } else if let bpm = Self.firstExplicitTempoBPM(
                    tempoEvents: combinedTempoEvents,
                    partID: scope.partID
                ) {
                    derivedTempoEvents.append(MusicXMLTempoEvent(
                        sourceID: marker.sourceID,
                        tick: marker.tick,
                        quarterBPM: bpm,
                        scope: scope
                    ))
                    annotations.append(marker.annotation(kind: tempoKind, resolution: .tempoEvent))
                } else {
                    annotations.append(marker.annotation(
                        kind: tempoKind,
                        resolution: .approximation(reason: "tempo-primo-missing-first-anchor")
                    ))
                }

            case .doppioMovimento:
                if let bpm = Self.lastExplicitTempoBPM(
                    atOrBeforeTick: marker.tick,
                    tempoEvents: combinedTempoEvents,
                    partID: scope.partID
                ) {
                    derivedTempoEvents.append(MusicXMLTempoEvent(
                        sourceID: marker.sourceID,
                        tick: marker.tick,
                        quarterBPM: bpm * 2,
                        scope: scope
                    ))
                    annotations.append(marker.annotation(kind: tempoKind, resolution: .tempoEvent))
                } else {
                    annotations.append(marker.annotation(
                        kind: tempoKind,
                        resolution: .approximation(reason: "doppio-movimento-missing-anchor")
                    ))
                }

            case .pedalDown, .pedalUp:
                break
            }
        }

        return MusicXMLWordsSemanticsResult(
            derivedTempoEvents: Self.dedupTempoEvents(derivedTempoEvents),
            derivedTempoRamps: derivedTempoRamps.sorted(by: Self.rampOrder),
            derivedPedalEvents: pedalEvents,
            tempoAnnotations: annotations
        )
    }
}

private extension MusicXMLWordsSemanticsInterpreter {
    enum RampDirection {
        case slower
        case faster
    }

    struct Marker: Equatable {
        enum Kind: Equatable {
            case ritardando
            case rallentando
            case accelerando
            case stringendo
            case aTempo
            case tempoPrimo
            case doppioMovimento
            case menoMosso
            case pedalDown
            case pedalUp

            var sortPriority: Int {
                switch self {
                case .pedalUp: 0
                case .pedalDown: 1
                case .aTempo, .tempoPrimo, .doppioMovimento, .menoMosso: 2
                case .ritardando, .rallentando: 3
                case .accelerando, .stringendo: 4
                }
            }

            var tempoKind: MusicXMLTempoWordKind? {
                switch self {
                case .ritardando: .ritardando
                case .rallentando: .rallentando
                case .accelerando: .accelerando
                case .stringendo: .stringendo
                case .aTempo: .aTempo
                case .tempoPrimo: .tempoPrimo
                case .doppioMovimento: .doppioMovimento
                case .menoMosso: .menoMosso
                case .pedalDown, .pedalUp: nil
                }
            }

            var startsTempoTransition: Bool {
                switch self {
                case .ritardando, .rallentando, .accelerando, .stringendo, .menoMosso:
                    true
                case .aTempo, .tempoPrimo, .doppioMovimento, .pedalDown, .pedalUp:
                    false
                }
            }
        }

        let sourceID: MusicXMLDirectionSourceID?
        let tick: Int
        let text: String
        let scope: MusicXMLEventScope
        let kind: Kind

        func annotation(
            kind: MusicXMLTempoWordKind,
            resolution: MusicXMLTempoWordResolution
        ) -> MusicXMLTempoWordAnnotation {
            MusicXMLTempoWordAnnotation(
                sourceID: sourceID,
                tick: tick,
                text: text,
                scope: scope,
                kind: kind,
                resolution: resolution
            )
        }
    }

    static func marker(from event: MusicXMLWordsEvent) -> Marker? {
        let normalized = normalizeWords(event.text)
        guard normalized.isEmpty == false else { return nil }
        let tokens = tokenize(normalized)

        if tokens == ["ped"] {
            return Marker(sourceID: event.sourceID, tick: event.tick, text: event.text, scope: event.scope, kind: .pedalDown)
        }
        if tokens == ["*"] {
            return Marker(sourceID: event.sourceID, tick: event.tick, text: event.text, scope: event.scope, kind: .pedalUp)
        }
        if normalized.contains("tempo primo") || tokens.contains("tempoprimo") {
            return Marker(sourceID: event.sourceID, tick: event.tick, text: event.text, scope: event.scope, kind: .tempoPrimo)
        }
        if normalized.contains("a tempo") || tokens.contains("atempo") {
            return Marker(sourceID: event.sourceID, tick: event.tick, text: event.text, scope: event.scope, kind: .aTempo)
        }
        if normalized.contains("doppio movimento") || tokens.contains("doppio") {
            return Marker(sourceID: event.sourceID, tick: event.tick, text: event.text, scope: event.scope, kind: .doppioMovimento)
        }
        if normalized.contains("meno mosso") {
            return Marker(sourceID: event.sourceID, tick: event.tick, text: event.text, scope: event.scope, kind: .menoMosso)
        }
        if tokens.contains(where: { ["rall", "rallentando"].contains($0) }) {
            return Marker(sourceID: event.sourceID, tick: event.tick, text: event.text, scope: event.scope, kind: .rallentando)
        }
        if tokens.contains(where: { ["rit", "ritard", "ritardando"].contains($0) }) {
            return Marker(sourceID: event.sourceID, tick: event.tick, text: event.text, scope: event.scope, kind: .ritardando)
        }
        if tokens.contains(where: { ["accel", "accelerando"].contains($0) }) {
            return Marker(sourceID: event.sourceID, tick: event.tick, text: event.text, scope: event.scope, kind: .accelerando)
        }
        if tokens.contains("stringendo") {
            return Marker(sourceID: event.sourceID, tick: event.tick, text: event.text, scope: event.scope, kind: .stringendo)
        }
        return nil
    }

    static func pedalEvent(from marker: Marker) -> MusicXMLPedalEvent? {
        switch marker.kind {
        case .pedalDown:
            MusicXMLPedalEvent(
                sourceID: marker.sourceID,
                partID: marker.scope.partID,
                measureNumber: 0,
                tick: marker.tick,
                kind: .start,
                isDown: true,
                timeOnlyPasses: nil
            )
        case .pedalUp:
            MusicXMLPedalEvent(
                sourceID: marker.sourceID,
                partID: marker.scope.partID,
                measureNumber: 0,
                tick: marker.tick,
                kind: .stop,
                isDown: false,
                timeOnlyPasses: nil
            )
        default:
            nil
        }
    }

    static func normalizeWords(_ text: String) -> String {
        text
            .replacing("\n", with: " ")
            .replacing("\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    static func tokenize(_ text: String) -> [String] {
        text
            .split(whereSeparator: { $0.isWhitespace })
            .map { token in
                token.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:()[]{}\"'"))
            }
            .filter { $0.isEmpty == false }
    }

    static func validatedTempoEvents(_ events: [MusicXMLTempoEvent]) -> [MusicXMLTempoEvent] {
        dedupTempoEvents(events.filter { $0.quarterBPM.isFinite && $0.quarterBPM > 0 })
    }

    static func hasExplicitTempo(
        atTick tick: Int,
        tempoEvents: [MusicXMLTempoEvent],
        partID: String
    ) -> Bool {
        tempoEvents.contains { $0.scope.partID == partID && $0.tick == tick }
    }

    static func firstExplicitTempoBPM(
        tempoEvents: [MusicXMLTempoEvent],
        partID: String
    ) -> Double? {
        tempoEvents.first(where: { $0.scope.partID == partID })?.quarterBPM
    }

    static func aTempoAnchorBPM(
        markerIndex: Int,
        markers: [Marker],
        tempoEvents: [MusicXMLTempoEvent],
        partID: String
    ) -> Double? {
        let transitionTick = markers[..<markerIndex]
            .reversed()
            .first(where: { $0.scope.partID == partID && $0.kind.startsTempoTransition })?
            .tick
        let anchorTick = transitionTick ?? markers[markerIndex].tick
        return lastExplicitTempoBPM(
            atOrBeforeTick: anchorTick,
            tempoEvents: tempoEvents,
            partID: partID
        )
    }

    static func lastExplicitTempoBPM(
        atOrBeforeTick tick: Int,
        tempoEvents: [MusicXMLTempoEvent],
        partID: String
    ) -> Double? {
        tempoEvents
            .filter { $0.scope.partID == partID && $0.tick <= tick }
            .max(by: tempoEventOrder)?
            .quarterBPM
    }

    static func nextExplicitTempo(
        afterTick tick: Int,
        tempoEvents: [MusicXMLTempoEvent],
        partID: String
    ) -> MusicXMLTempoEvent? {
        tempoEvents
            .filter { $0.scope.partID == partID && $0.tick > tick }
            .min(by: tempoEventOrder)
    }

    static func tempoRampIfPossible(
        startTick: Int,
        direction: RampDirection,
        explicitTempoEvents: [MusicXMLTempoEvent],
        scope: MusicXMLEventScope
    ) -> MusicXMLTempoMap.TempoRamp? {
        guard let startBPM = lastExplicitTempoBPM(
            atOrBeforeTick: startTick,
            tempoEvents: explicitTempoEvents,
            partID: scope.partID
        ),
        let endEvent = nextExplicitTempo(
            afterTick: startTick,
            tempoEvents: explicitTempoEvents,
            partID: scope.partID
        ) else {
            return nil
        }

        switch direction {
        case .slower where endEvent.quarterBPM >= startBPM:
            return nil
        case .faster where endEvent.quarterBPM <= startBPM:
            return nil
        default:
            break
        }

        return MusicXMLTempoMap.TempoRamp(
            startTick: startTick,
            endTick: endEvent.tick,
            startQuarterBPM: startBPM,
            endQuarterBPM: endEvent.quarterBPM,
            scope: scope
        )
    }

    static func dedupTempoEvents(_ events: [MusicXMLTempoEvent]) -> [MusicXMLTempoEvent] {
        var bestByKey: [String: MusicXMLTempoEvent] = [:]
        for event in events.sorted(by: tempoEventOrder) {
            let staffKey = event.scope.staff.map(String.init) ?? "_"
            let voiceKey = event.scope.voice.map(String.init) ?? "_"
            let key = "\(event.scope.partID)-\(staffKey)-\(voiceKey)-\(event.tick)"
            if let current = bestByKey[key] {
                let currentID = current.sourceID?.description ?? ""
                let candidateID = event.sourceID?.description ?? ""
                if candidateID > currentID {
                    bestByKey[key] = event
                }
            } else {
                bestByKey[key] = event
            }
        }
        return bestByKey.values.sorted(by: tempoEventOrder)
    }

    static func markerOrder(_ lhs: Marker, _ rhs: Marker) -> Bool {
        if lhs.scope.partID != rhs.scope.partID { return lhs.scope.partID < rhs.scope.partID }
        if lhs.tick != rhs.tick { return lhs.tick < rhs.tick }
        if lhs.kind.sortPriority != rhs.kind.sortPriority { return lhs.kind.sortPriority < rhs.kind.sortPriority }
        return (lhs.sourceID?.description ?? "") < (rhs.sourceID?.description ?? "")
    }

    static func tempoEventOrder(_ lhs: MusicXMLTempoEvent, _ rhs: MusicXMLTempoEvent) -> Bool {
        if lhs.scope.partID != rhs.scope.partID { return lhs.scope.partID < rhs.scope.partID }
        if lhs.tick != rhs.tick { return lhs.tick < rhs.tick }
        let lhsSpecificity = (lhs.scope.staff == nil ? 0 : 1) + (lhs.scope.voice == nil ? 0 : 2)
        let rhsSpecificity = (rhs.scope.staff == nil ? 0 : 1) + (rhs.scope.voice == nil ? 0 : 2)
        if lhsSpecificity != rhsSpecificity { return lhsSpecificity < rhsSpecificity }
        return (lhs.sourceID?.description ?? "") < (rhs.sourceID?.description ?? "")
    }

    static func rampOrder(_ lhs: MusicXMLTempoMap.TempoRamp, _ rhs: MusicXMLTempoMap.TempoRamp) -> Bool {
        if lhs.scope.partID != rhs.scope.partID { return lhs.scope.partID < rhs.scope.partID }
        if lhs.startTick != rhs.startTick { return lhs.startTick < rhs.startTick }
        return lhs.endTick < rhs.endTick
    }
}
