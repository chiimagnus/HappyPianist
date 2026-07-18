import Foundation

extension MusicXMLParserDelegate {
    func moveCurrentTick(by delta: Int) {
        let current = state.partTick[state.currentPartID] ?? state.currentMeasureStartTick
        let moved = max(state.currentMeasureStartTick, current + delta)
        state.partTick[state.currentPartID] = moved
        let currentMax = state.partMeasureMaxTick[state.currentPartID] ?? state.currentMeasureStartTick
        state.partMeasureMaxTick[state.currentPartID] = max(currentMax, moved)
    }

    func normalizeDuration(_ rawDuration: Int) -> Int {
        let divisions = max(1, state.partDivisions[state.currentPartID] ?? 1)
        let normalized = Double(rawDuration) * Double(state.normalizedTicksPerQuarter) / Double(divisions)
        return max(0, Int(normalized.rounded()))
    }

    func normalizeSignedDuration(_ rawDuration: Int) -> Int {
        if rawDuration == 0 {
            return 0
        }
        let sign = rawDuration >= 0 ? 1 : -1
        let normalized = normalizeDuration(abs(rawDuration))
        return sign * normalized
    }


    func parseMeterBeatGroups(_ raw: String) -> [Int]? {
        let groups = raw.split(separator: "+").compactMap { token -> Int? in
            let value = Int(token.trimmingCharacters(in: .whitespacesAndNewlines))
            return value.flatMap { $0 > 0 ? $0 : nil }
        }
        return groups.isEmpty ? nil : groups
    }

    func makeCurrentMeter() -> MusicXMLMeter? {
        if state.timeIsSenzaMisura {
            return MusicXMLMeter(
                components: [],
                symbolToken: state.timeSymbolToken,
                isSenzaMisura: true,
                approximation: nil
            )
        }
        guard state.timeBeatGroups.isEmpty == false,
              state.timeBeatTypes.isEmpty == false
        else { return nil }

        let fallbackBeatType = state.timeBeatTypes.last ?? 4
        let components = state.timeBeatGroups.enumerated().map { index, groups in
            MusicXMLMeter.Component(
                beatGroups: groups,
                beatType: state.timeBeatTypes.indices.contains(index)
                    ? state.timeBeatTypes[index]
                    : fallbackBeatType
            )
        }
        let approximation = state.timeBeatGroups.count == state.timeBeatTypes.count
            ? nil
            : "beat-group-count-mismatch"
        return MusicXMLMeter(
            components: components,
            symbolToken: state.timeSymbolToken,
            isSenzaMisura: false,
            approximation: approximation
        )
    }
}
