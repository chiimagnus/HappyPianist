import MusicXML
import Practice

struct GrandStaffNotationAccessibilityDescriptor: Equatable {
    struct Element: Equatable, Identifiable {
        let id: String
        let label: String
    }

    let containerLabel: String
    let containerValue: String
    let elements: [Element]

    static func make(
        projection: ScoreNotationProjection,
        layout: GrandStaffNotationLayout,
        measureSpans: [MusicXMLMeasureSpan],
        currentTick: Int?,
        activeTickRange: Range<Int>? = nil
    ) -> Self {
        let occurrencesByID = Dictionary(
            uniqueKeysWithValues: projection.performedOccurrences.map { ($0.id.description, $0) }
        )
        let sourceNotesByID = Dictionary(uniqueKeysWithValues: projection.sourceNotes.map { ($0.id, $0) })
        let fallbacksBySourceID = Dictionary(grouping: projection.fallbacks, by: \.sourceID)

        func source(for occurrenceID: String) -> ScoreNotationProjection.SourceNote? {
            occurrencesByID[occurrenceID].flatMap { sourceNotesByID[$0.sourceNoteID] }
        }

        func unsupportedDescription(for occurrenceID: String) -> String? {
            guard let source = source(for: occurrenceID),
                  let fallback = fallbacksBySourceID[source.id]?.first
            else { return nil }
            return switch fallback.placeholderPolicy {
            case .omit: "不支持的记谱内容，已省略图形"
            case .reserveRhythmicSpace: "不支持的记谱内容，已保留节奏占位"
            }
        }

        let notes = layout.items.sorted(by: elementOrder).map { item in
            let sourceNote = source(for: item.occurrenceID)
            var components = [staffDescription(item.staffNumber)]
            if let pitch = pitchDescription(sourceNote) { components.append(pitch) }
            components.append("音符")
            if item.isHighlighted { components.append("当前高亮") }
            if let activeTickRange, !activeTickRange.contains(item.tick) { components.append("练习范围外") }
            if let fingering = item.fingerings.fingeringDisplayText {
                components.append("指法 \(fingering)")
            }
            if let unsupported = unsupportedDescription(for: item.occurrenceID) {
                components.append(unsupported)
            }
            return Element(id: "note:\(item.id)", label: components.joined(separator: "，"))
        }
        let rests = layout.rests.sorted(by: elementOrder).map { rest in
            var components = [staffDescription(rest.staffNumber), "休止符"]
            if rest.isHighlighted { components.append("当前高亮") }
            if let activeTickRange, !activeTickRange.contains(rest.tick) { components.append("练习范围外") }
            if let unsupported = unsupportedDescription(for: rest.id) {
                components.append(unsupported)
            }
            return Element(id: "rest:\(rest.id)", label: components.joined(separator: "，"))
        }

        let resolvedTick = currentTick
            ?? layout.items.first?.tick
            ?? layout.rests.first?.tick
            ?? 0
        let currentMeasure = measureSpans.first {
            $0.startTick <= resolvedTick && resolvedTick < $0.endTick
        } ?? measureSpans.last(where: { $0.startTick <= resolvedTick })
        var measurePrefix = currentMeasure.map {
            "第 \($0.sourceMeasureNumberToken ?? $0.measureNumber.formatted()) 小节"
        } ?? "当前窗口"
        if currentTick == nil, let first = measureSpans.first, let last = measureSpans.last, first.id != last.id {
            measurePrefix = "第 \(first.sourceMeasureNumberToken ?? first.measureNumber.formatted()) 至 \(last.sourceMeasureNumberToken ?? last.measureNumber.formatted()) 小节"
        }
        let signatures = [layout.context?.treble, layout.context?.bass].compactMap { staff -> String? in
            guard let staff else { return nil }
            return [staff.clefGlyph == nil ? "不支持的谱号 \(staff.clefSign)" : nil, staff.meter.map { "拍号 \($0)" }].compactMap { $0 }.joined(separator: "，")
        }.filter { !$0.isEmpty }.joined(separator: "，")

        return Self(
            containerLabel: "Grand Staff 五线谱",
            containerValue: "\(measurePrefix)，\(notes.count) 个音符，\(rests.count) 个休止符" + (signatures.isEmpty ? "" : "，\(signatures)"),
            elements: (notes + rests).sorted { first, second in
                func order(_ element: Element) -> (Int, Int, Int, Int) {
                    if let item = layout.items.first(where: { "note:" + $0.id == element.id }) {
                        return (item.tick, item.staffNumber, item.voice, source(for: item.occurrenceID)?.id.sourceOrdinal ?? 0)
                    }
                    if let rest = layout.rests.first(where: { "rest:" + $0.id == element.id }) {
                        return (rest.tick, rest.staffNumber, rest.voice, source(for: rest.id)?.id.sourceOrdinal ?? 0)
                    }
                    return (0, 0, 0, 0)
                }
                return order(first) < order(second)
            }
        )
    }

    private static func staffDescription(_ staffNumber: Int) -> String {
        staffNumber >= 2 ? "下谱表" : "上谱表"
    }

    private static func pitchDescription(_ source: ScoreNotationProjection.SourceNote?) -> String? {
        guard let pitch = source?.writtenPitch else { return nil }
        return "\(pitch.step)\(pitch.octave)"
    }

    private static func elementOrder(_ lhs: GrandStaffNotationItem, _ rhs: GrandStaffNotationItem) -> Bool {
        if lhs.tick != rhs.tick { return lhs.tick < rhs.tick }
        if lhs.staffNumber != rhs.staffNumber { return lhs.staffNumber < rhs.staffNumber }
        if lhs.voice != rhs.voice { return lhs.voice < rhs.voice }
        return lhs.id < rhs.id
    }

    private static func elementOrder(_ lhs: GrandStaffNotationRest, _ rhs: GrandStaffNotationRest) -> Bool {
        if lhs.tick != rhs.tick { return lhs.tick < rhs.tick }
        if lhs.staffNumber != rhs.staffNumber { return lhs.staffNumber < rhs.staffNumber }
        if lhs.voice != rhs.voice { return lhs.voice < rhs.voice }
        return lhs.id < rhs.id
    }
}
