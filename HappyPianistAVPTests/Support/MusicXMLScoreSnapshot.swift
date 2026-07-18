@testable import HappyPianistAVP

struct MusicXMLScoreSnapshot {
    private let encoder = PianoPerformanceSnapshotEncoder()

    func encode(_ score: MusicXMLScore) -> String {
        var lines: [String] = [
            encoder.encode(fields: [
                ("score.version", score.scoreVersion),
                ("score.noteCount", String(score.notes.count)),
                ("score.measureCount", String(score.measures.count)),
            ]),
        ]

        lines.append(contentsOf: score.notes.enumerated().map(noteLine))
        lines.append(contentsOf: score.tempoEvents.enumerated().map { index, event in
            directionLine(
                kind: "tempo",
                index: index,
                tick: event.tick,
                scope: event.scope,
                value: encoder.encode(event.quarterBPM)
            )
        })
        lines.append(contentsOf: score.dynamicEvents.enumerated().map { index, event in
            directionLine(
                kind: "dynamic",
                index: index,
                tick: event.tick,
                scope: event.scope,
                value: String(event.velocity)
            )
        })
        lines.append(contentsOf: score.wedgeEvents.enumerated().map { index, event in
            directionLine(
                kind: "wedge",
                index: index,
                tick: event.tick,
                scope: event.scope,
                value: "\(event.kind):\(event.numberToken ?? "null")"
            )
        })
        lines.append(contentsOf: score.pedalEvents.enumerated().map { index, event in
            encoder.encode(fields: [
                ("kind", "pedal"),
                ("sourceDirectionID", "unresolved"),
                ("sourceIndex", String(index)),
                ("part", event.partID),
                ("measure", String(event.measureNumber)),
                ("tick", String(event.tick)),
                ("event", event.kind.rawValue),
                ("down", encoder.encode(event.isDown)),
            ])
        })
        lines.append(contentsOf: score.fermataEvents.enumerated().map { index, event in
            directionLine(
                kind: "fermata",
                index: index,
                tick: event.tick,
                scope: event.scope,
                value: String(describing: event.source)
            )
        })
        lines.append(contentsOf: score.wordsEvents.enumerated().map { index, event in
            directionLine(
                kind: "words",
                index: index,
                tick: event.tick,
                scope: event.scope,
                value: event.text
            )
        })
        lines.append(contentsOf: score.soundDirectives.enumerated().map { index, event in
            encoder.encode(fields: [
                ("kind", "sound"),
                ("sourceDirectionID", "unresolved"),
                ("sourceIndex", String(index)),
                ("part", event.partID),
                ("measure", String(event.measureNumber)),
                ("tick", String(event.tick)),
                ("segno", event.segno),
                ("coda", event.coda),
                ("tocoda", event.tocoda),
                ("dalsegno", event.dalsegno),
                ("dacapo", event.dacapo),
            ])
        })
        lines.append(contentsOf: score.measures.sorted(by: measureOrdering).map { measure in
            encoder.encode(fields: [
                ("kind", "measure"),
                ("sourceMeasureID", sourceMeasureID(measure.sourceMeasureID)),
                ("occurrenceID", occurrenceID(measure.occurrenceID)),
                ("part", measure.partID),
                ("number", String(measure.measureNumber)),
                ("sourceIndex", String(measure.sourceMeasureIndex)),
                ("sourceToken", measure.sourceMeasureNumberToken),
                ("start", String(measure.startTick)),
                ("end", String(measure.endTick)),
            ])
        })
        lines.append(contentsOf: score.repeatDirectives.enumerated().map { index, directive in
            encoder.encode(fields: [
                ("kind", "repeat"),
                ("sourceIndex", String(index)),
                ("part", directive.partID),
                ("measure", String(directive.measureNumber)),
                ("direction", directive.direction.rawValue),
            ])
        })
        lines.append(contentsOf: score.endingDirectives.enumerated().map { index, directive in
            encoder.encode(fields: [
                ("kind", "ending"),
                ("sourceIndex", String(index)),
                ("part", directive.partID),
                ("measure", String(directive.measureNumber)),
                ("number", directive.number),
                ("type", directive.type.rawValue),
            ])
        })

        return encoder.encode(lines: lines)
    }

    private func noteLine(index: Int, note: MusicXMLNoteEvent) -> String {
        encoder.encode(fields: [
            ("kind", "note"),
            ("sourceNoteID", note.sourceID?.description ?? "unresolved"),
            ("sourceIndex", String(index)),
            ("part", note.partID),
            ("measure", String(note.measureNumber)),
            ("tick", String(note.tick)),
            ("duration", String(note.durationTicks)),
            ("midi", encoder.encode(note.midiNote)),
            ("rest", encoder.encode(note.isRest)),
            ("chord", encoder.encode(note.isChord)),
            ("grace", encoder.encode(note.isGrace)),
            ("staff", encoder.encode(note.staff)),
            ("voice", encoder.encode(note.voice)),
            ("tieStart", encoder.encode(note.tieStart)),
            ("tieStop", encoder.encode(note.tieStop)),
        ])
    }

    private func directionLine(
        kind: String,
        index: Int,
        tick: Int,
        scope: MusicXMLEventScope,
        value: String
    ) -> String {
        encoder.encode(fields: [
            ("kind", kind),
            ("sourceDirectionID", "unresolved"),
            ("sourceIndex", String(index)),
            ("part", scope.partID),
            ("staff", encoder.encode(scope.staff)),
            ("voice", encoder.encode(scope.voice)),
            ("tick", String(tick)),
            ("value", value),
        ])
    }

    private func sourceMeasureID(_ id: PracticeSourceMeasureID) -> String {
        "\(id.partID):\(id.sourceMeasureIndex):\(id.sourceNumberToken ?? "null")"
    }

    private func occurrenceID(_ id: PracticeMeasureOccurrenceID) -> String {
        "\(sourceMeasureID(id.sourceMeasureID))#\(id.occurrenceIndex)"
    }

    private func measureOrdering(_ lhs: MusicXMLMeasureSpan, _ rhs: MusicXMLMeasureSpan) -> Bool {
        if lhs.partID != rhs.partID { return lhs.partID < rhs.partID }
        if lhs.sourceMeasureIndex != rhs.sourceMeasureIndex {
            return lhs.sourceMeasureIndex < rhs.sourceMeasureIndex
        }
        if lhs.occurrenceIndex != rhs.occurrenceIndex {
            return lhs.occurrenceIndex < rhs.occurrenceIndex
        }
        return lhs.startTick < rhs.startTick
    }
}
