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
}
