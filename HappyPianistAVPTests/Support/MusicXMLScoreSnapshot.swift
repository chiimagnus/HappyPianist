import Foundation
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

        lines.append(contentsOf: canonicalLines(score.notes, sortKey: noteSortKey, encode: noteLine))
        lines.append(contentsOf: canonicalLines(score.tempoEvents, sortKey: { event, fallback in
            directionSortKey(sourceID: event.sourceID, tick: event.tick, scope: event.scope, fallback: fallback)
        }) { index, event in
            directionLine(
                kind: "tempo",
                sourceID: event.sourceID,
                index: index,
                tick: event.tick,
                scope: event.scope,
                value: encoder.encode(event.quarterBPM)
            )
        })
        lines.append(contentsOf: canonicalLines(score.dynamicEvents, sortKey: { event, fallback in
            directionSortKey(sourceID: event.sourceID, tick: event.tick, scope: event.scope, fallback: fallback)
        }) { index, event in
            directionLine(
                kind: "dynamic",
                sourceID: event.sourceID,
                index: index,
                tick: event.tick,
                scope: event.scope,
                value: String(event.velocity)
            )
        })
        lines.append(contentsOf: canonicalLines(score.wedgeEvents, sortKey: { event, fallback in
            directionSortKey(sourceID: event.sourceID, tick: event.tick, scope: event.scope, fallback: fallback)
        }) { index, event in
            directionLine(
                kind: "wedge",
                sourceID: event.sourceID,
                index: index,
                tick: event.tick,
                scope: event.scope,
                value: "\(event.kind):\(event.numberToken ?? "null")"
            )
        })
        lines.append(contentsOf: canonicalLines(
            score.pedalEvents,
            sortKey: pedalSortKey,
            encode: pedalLine
        ))
        lines.append(contentsOf: canonicalLines(score.fermataEvents, sortKey: { event, fallback in
            directionSortKey(sourceID: event.sourceID, tick: event.tick, scope: event.scope, fallback: fallback)
        }) { index, event in
            directionLine(
                kind: "fermata",
                sourceID: event.sourceID,
                index: index,
                tick: event.tick,
                scope: event.scope,
                value: String(describing: event.source)
            )
        })
        lines.append(contentsOf: canonicalLines(score.wordsEvents, sortKey: { event, fallback in
            directionSortKey(sourceID: event.sourceID, tick: event.tick, scope: event.scope, fallback: fallback)
        }) { index, event in
            directionLine(
                kind: "words",
                sourceID: event.sourceID,
                index: index,
                tick: event.tick,
                scope: event.scope,
                value: event.text
            )
        })
        lines.append(contentsOf: canonicalLines(score.soundDirectives, sortKey: { event, fallback in
            directionSortKey(
                sourceID: event.sourceID,
                tick: event.tick,
                scope: MusicXMLEventScope(partID: event.partID, staff: nil, voice: nil),
                fallback: fallback
            )
        }) { index, event in
            encoder.encode(fields: [
                ("kind", "sound"),
                ("sourceDirectionID", event.sourceID?.description ?? "unresolved"),
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
        lines.append(contentsOf: canonicalLines(score.timeSignatureEvents, sortKey: { event, fallback in
            SnapshotSortKey(tick: event.tick, scope: event.scope, fallback: fallback)
        }) { index, event in
            encoder.encode(fields: [
                ("kind", "meter"),
                ("sourceIndex", String(index)),
                ("part", event.scope.partID),
                ("tick", String(event.tick)),
                ("value", event.meter.displayText),
                ("symbol", event.meter.symbolToken),
                ("approximation", event.meter.approximation),
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
        lines.append(contentsOf: canonicalLines(score.repeatDirectives, sortKey: { directive, fallback in
            SnapshotSortKey(
                tick: directive.measureNumber,
                scope: MusicXMLEventScope(partID: directive.partID, staff: nil, voice: nil),
                fallback: fallback
            )
        }) { index, directive in
            encoder.encode(fields: [
                ("kind", "repeat"),
                ("sourceIndex", String(index)),
                ("part", directive.partID),
                ("measure", String(directive.measureNumber)),
                ("direction", directive.direction.rawValue),
                ("times", directive.times.map(String.init)),
            ])
        })
        lines.append(contentsOf: canonicalLines(score.endingDirectives, sortKey: { directive, fallback in
            SnapshotSortKey(
                tick: directive.measureNumber,
                scope: MusicXMLEventScope(partID: directive.partID, staff: nil, voice: nil),
                fallback: fallback
            )
        }) { index, directive in
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
            ("tieStart", encoder.encode(note.startsTie)),
            ("tieStop", encoder.encode(note.stopsTie)),
        ])
    }

    private func pedalLine(index: Int, event: MusicXMLPedalEvent) -> String {
        encoder.encode(fields: [
            ("kind", "pedal"),
            ("sourceDirectionID", event.sourceID?.description ?? "unresolved"),
            ("sourceIndex", String(index)),
            ("part", event.partID),
            ("measure", String(event.measureNumber)),
            ("tick", String(event.tick)),
            ("event", event.kind.rawValue),
            ("controller", String(event.controller.rawValue)),
            ("value", event.value.map { String($0.midiValue) }),
            ("sourcePercentage", event.value.map { NSDecimalNumber(decimal: $0.percentage).stringValue }),
        ])
    }

    private func pedalSortKey(_ event: MusicXMLPedalEvent, fallback: String) -> SnapshotSortKey {
        directionSortKey(
            sourceID: event.sourceID,
            tick: event.tick,
            scope: MusicXMLEventScope(partID: event.partID, staff: nil, voice: nil),
            fallback: fallback
        )
    }

    private func directionLine(
        kind: String,
        sourceID: MusicXMLDirectionSourceID?,
        index: Int,
        tick: Int,
        scope: MusicXMLEventScope,
        value: String
    ) -> String {
        encoder.encode(fields: [
            ("kind", kind),
            ("sourceDirectionID", sourceID?.description ?? "unresolved"),
            ("sourceIndex", String(index)),
            ("part", scope.partID),
            ("staff", encoder.encode(scope.staff)),
            ("voice", encoder.encode(scope.voice)),
            ("tick", String(tick)),
            ("value", value),
        ])
    }

    private func canonicalLines<Element>(
        _ elements: [Element],
        sortKey: (Element, String) -> SnapshotSortKey,
        encode: (Int, Element) -> String
    ) -> [String] {
        elements
            .map { element in (element, sortKey(element, encode(0, element))) }
            .sorted { $0.1 < $1.1 }
            .enumerated()
            .map { index, entry in encode(index, entry.0) }
    }

    private func noteSortKey(_ note: MusicXMLNoteEvent, fallback: String) -> SnapshotSortKey {
        SnapshotSortKey(
            sourcePartID: note.sourceID?.partID,
            sourceMeasureIndex: note.sourceID?.sourceMeasureIndex,
            sourceStaff: note.sourceID?.staff,
            sourceVoice: note.sourceID?.voice,
            sourceOrdinal: note.sourceID?.sourceOrdinal,
            tick: note.tick,
            scope: MusicXMLEventScope(partID: note.partID, staff: note.staff, voice: note.voice),
            fallback: fallback
        )
    }

    private func directionSortKey(
        sourceID: MusicXMLDirectionSourceID?,
        tick: Int,
        scope: MusicXMLEventScope,
        fallback: String
    ) -> SnapshotSortKey {
        SnapshotSortKey(
            sourcePartID: sourceID?.partID,
            sourceMeasureIndex: sourceID?.sourceMeasureIndex,
            sourceOrdinal: sourceID?.sourceOrdinal,
            tick: tick,
            scope: scope,
            fallback: fallback
        )
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

    private struct SnapshotSortKey: Comparable {
        var sourcePartID: String?
        var sourceMeasureIndex: Int?
        var sourceStaff: Int?
        var sourceVoice: Int?
        var sourceOrdinal: Int?
        let tick: Int
        let scope: MusicXMLEventScope
        let fallback: String

        init(
            sourcePartID: String? = nil,
            sourceMeasureIndex: Int? = nil,
            sourceStaff: Int? = nil,
            sourceVoice: Int? = nil,
            sourceOrdinal: Int? = nil,
            tick: Int,
            scope: MusicXMLEventScope,
            fallback: String
        ) {
            self.sourcePartID = sourcePartID
            self.sourceMeasureIndex = sourceMeasureIndex
            self.sourceStaff = sourceStaff
            self.sourceVoice = sourceVoice
            self.sourceOrdinal = sourceOrdinal
            self.tick = tick
            self.scope = scope
            self.fallback = fallback
        }

        static func < (lhs: Self, rhs: Self) -> Bool {
            if lhs.sourcePartID != rhs.sourcePartID { return (lhs.sourcePartID ?? "~") < (rhs.sourcePartID ?? "~") }
            if lhs.sourceMeasureIndex != rhs.sourceMeasureIndex {
                return (lhs.sourceMeasureIndex ?? .max) < (rhs.sourceMeasureIndex ?? .max)
            }
            if lhs.sourceStaff != rhs.sourceStaff { return (lhs.sourceStaff ?? .max) < (rhs.sourceStaff ?? .max) }
            if lhs.sourceVoice != rhs.sourceVoice { return (lhs.sourceVoice ?? .max) < (rhs.sourceVoice ?? .max) }
            if lhs.sourceOrdinal != rhs.sourceOrdinal { return (lhs.sourceOrdinal ?? .max) < (rhs.sourceOrdinal ?? .max) }
            if lhs.tick != rhs.tick { return lhs.tick < rhs.tick }
            if lhs.scope.partID != rhs.scope.partID { return lhs.scope.partID < rhs.scope.partID }
            if lhs.scope.staff != rhs.scope.staff { return (lhs.scope.staff ?? .max) < (rhs.scope.staff ?? .max) }
            if lhs.scope.voice != rhs.scope.voice { return (lhs.scope.voice ?? .max) < (rhs.scope.voice ?? .max) }
            return lhs.fallback < rhs.fallback
        }
    }
}
