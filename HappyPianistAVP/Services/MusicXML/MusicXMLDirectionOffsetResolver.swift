import Foundation

struct MusicXMLDirectionOffsetResolver: Sendable {
    let ticksPerQuarter: Int

    init(ticksPerQuarter: Int = 480) {
        self.ticksPerQuarter = max(1, ticksPerQuarter)
    }

    func offsetTicks(rawDivisions: Double, divisions: Int?) -> Int? {
        guard rawDivisions.isFinite else { return nil }
        let resolvedDivisions = max(1, divisions ?? 1)
        let ticks = rawDivisions * Double(ticksPerQuarter) / Double(resolvedDivisions)
        guard ticks.isFinite else { return nil }
        return Int(ticks.rounded(.toNearestOrAwayFromZero))
    }

    func absoluteTick(
        directionStartTick: Int,
        measureStartTick: Int,
        offsetTicks: Int
    ) -> Int {
        max(measureStartTick, directionStartTick + offsetTicks)
    }
}
