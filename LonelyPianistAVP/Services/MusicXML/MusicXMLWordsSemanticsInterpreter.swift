import Foundation

struct MusicXMLWordsSemanticsResult: Equatable {
    let derivedTempoEvents: [MusicXMLTempoEvent]
    let derivedTempoRamps: [MusicXMLTempoMap.TempoRamp]
    let derivedPedalEvents: [MusicXMLPedalEvent]
}

struct MusicXMLWordsSemanticsInterpreter {
    func interpret(
        wordsEvents: [MusicXMLWordsEvent],
        tempoEvents: [MusicXMLTempoEvent]
    ) -> MusicXMLWordsSemanticsResult {
        let markers = wordsEvents
            .compactMap(Self.marker(from:))
            .sorted { lhs, rhs in
                if lhs.tick != rhs.tick { return lhs.tick < rhs.tick }
                return lhs.kind.sortPriority < rhs.kind.sortPriority
            }

        let pedalEvents = markers.compactMap { marker -> MusicXMLPedalEvent? in
            switch marker.kind {
                case .pedalDown:
                    MusicXMLPedalEvent(
                        partID: marker.partID,
                        measureNumber: 0,
                        tick: marker.tick,
                        kind: .start,
                        isDown: true,
                        timeOnlyPasses: nil
                    )
                case .pedalUp:
                    MusicXMLPedalEvent(
                        partID: marker.partID,
                        measureNumber: 0,
                        tick: marker.tick,
                        kind: .stop,
                        isDown: false,
                        timeOnlyPasses: nil
                    )
                case .rit, .accel, .aTempo:
                    nil
            }
        }

        let validatedTempoEvents = tempoEvents
            .filter { $0.quarterBPM.isFinite && $0.quarterBPM > 0 }
            .sorted { lhs, rhs in
                if lhs.tick != rhs.tick { return lhs.tick < rhs.tick }
                return false
            }

        let aTempoEvents: [MusicXMLTempoEvent] = markers.compactMap { marker in
            guard marker.kind == .aTempo else { return nil }
            guard let bpm = Self.lastExplicitTempoBPM(atOrBeforeTick: marker.tick, tempoEvents: validatedTempoEvents)
            else {
                return nil
            }
            return MusicXMLTempoEvent(tick: marker.tick, quarterBPM: bpm)
        }

        let combinedTempoEvents = Self.dedupTempoEvents(validatedTempoEvents + aTempoEvents)

        let ramps: [MusicXMLTempoMap.TempoRamp] = markers.compactMap { marker in
            switch marker.kind {
                case .rit:
                    Self.tempoRampIfPossible(
                        startTick: marker.tick,
                        requiresSlowingDown: true,
                        explicitTempoEvents: combinedTempoEvents
                    )
                case .accel:
                    Self.tempoRampIfPossible(
                        startTick: marker.tick,
                        requiresSlowingDown: false,
                        explicitTempoEvents: combinedTempoEvents
                    )
                case .aTempo, .pedalDown, .pedalUp:
                    nil
            }
        }

        return MusicXMLWordsSemanticsResult(
            derivedTempoEvents: aTempoEvents,
            derivedTempoRamps: ramps,
            derivedPedalEvents: pedalEvents
        )
    }

    private struct Marker: Equatable {
        enum Kind: Equatable {
            case rit
            case accel
            case aTempo
            case pedalDown
            case pedalUp

            var sortPriority: Int {
                switch self {
                    case .pedalUp: 0
                    case .pedalDown: 1
                    case .aTempo: 2
                    case .rit: 3
                    case .accel: 4
                }
            }
        }

        let tick: Int
        let partID: String
        let kind: Kind
    }

    private static func marker(from event: MusicXMLWordsEvent) -> Marker? {
        let normalized = normalizeWords(event.text)
        guard normalized.isEmpty == false else { return nil }

        let tokens = tokenize(normalized)

        if tokens.first == "ped" {
            return Marker(tick: event.tick, partID: event.scope.partID, kind: .pedalDown)
        }

        if tokens.contains("*"), tokens.count == 1 {
            return Marker(tick: event.tick, partID: event.scope.partID, kind: .pedalUp)
        }

        if containsATempoPhrase(normalized, tokens: tokens) {
            return Marker(tick: event.tick, partID: event.scope.partID, kind: .aTempo)
        }

        if tokens.contains("rit") || tokens.contains("rit.") || tokens.contains("ritardando") {
            return Marker(tick: event.tick, partID: event.scope.partID, kind: .rit)
        }

        if tokens.contains("accel") || tokens.contains("accel.") || tokens.contains("accelerando") {
            return Marker(tick: event.tick, partID: event.scope.partID, kind: .accel)
        }

        return nil
    }

    private static func normalizeWords(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func tokenize(_ text: String) -> [String] {
        text
            .split(whereSeparator: { $0.isWhitespace })
            .map { token in
                token.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:()[]{}\"'"))
            }
            .filter { $0.isEmpty == false }
    }

    private static func containsATempoPhrase(_ normalizedText: String, tokens: [String]) -> Bool {
        if normalizedText.contains("a tempo") { return true }
        if tokens.contains("atempo") { return true }
        return false
    }

    private static func lastExplicitTempoBPM(atOrBeforeTick tick: Int, tempoEvents: [MusicXMLTempoEvent]) -> Double? {
        guard tempoEvents.isEmpty == false else { return nil }
        return tempoEvents
            .filter { $0.tick <= tick }
            .last?
            .quarterBPM
    }

    private static func nextExplicitTempo(
        afterTick tick: Int,
        tempoEvents: [MusicXMLTempoEvent]
    ) -> MusicXMLTempoEvent? {
        tempoEvents.first(where: { $0.tick > tick })
    }

    private static func dedupTempoEvents(_ events: [MusicXMLTempoEvent]) -> [MusicXMLTempoEvent] {
        var bpmByTick: [Int: Double] = [:]
        for event in events {
            bpmByTick[event.tick] = event.quarterBPM
        }
        return bpmByTick.keys.sorted().map { tick in
            MusicXMLTempoEvent(tick: tick, quarterBPM: bpmByTick[tick] ?? 120)
        }
    }

    private static func tempoRampIfPossible(
        startTick: Int,
        requiresSlowingDown: Bool,
        explicitTempoEvents: [MusicXMLTempoEvent]
    ) -> MusicXMLTempoMap.TempoRamp? {
        guard let startBPM = lastExplicitTempoBPM(atOrBeforeTick: startTick, tempoEvents: explicitTempoEvents)
        else { return nil }
        guard let endEvent = nextExplicitTempo(afterTick: startTick, tempoEvents: explicitTempoEvents)
        else { return nil }
        let endBPM = endEvent.quarterBPM

        if requiresSlowingDown, endBPM >= startBPM { return nil }
        if requiresSlowingDown == false, endBPM <= startBPM { return nil }

        return MusicXMLTempoMap.TempoRamp(
            startTick: startTick,
            endTick: endEvent.tick,
            startQuarterBPM: startBPM,
            endQuarterBPM: endBPM
        )
    }
}
