import Foundation


public struct MusicXMLDirectionOffsetResolver {
    public let ticksPerQuarter: Int

    public init(ticksPerQuarter: Int = 480) {
        self.ticksPerQuarter = max(1, ticksPerQuarter)
    }

    public func offsetTicks(rawDivisions: Double, divisions: Int?) -> Int? {
        guard rawDivisions.isFinite else { return nil }
        let resolvedDivisions = max(1, divisions ?? 1)
        let ticks = rawDivisions * Double(ticksPerQuarter) / Double(resolvedDivisions)
        guard ticks.isFinite else { return nil }
        return Int(ticks.rounded(.toNearestOrAwayFromZero))
    }

    public func absoluteTick(
        directionStartTick: Int,
        offsetTicks: Int
    ) -> Int {
        max(0, directionStartTick + offsetTicks)
    }
}
