@testable import HappyPianistAVP
import Testing

struct GrandStaffHorizontalSpacingServiceTests {
    private let service = GrandStaffHorizontalSpacingService()

    @Test
    func writtenDurationControlsRhythmicDistance() throws {
        let layout = service.makeLayout(rhythmicColumns: [
            column(tick: 0, duration: 120),
            column(tick: 120, duration: 480),
            column(tick: 600, duration: 120),
        ])
        let first = try #require(layout.rhythmicPositionsByTick[0])
        let second = try #require(layout.rhythmicPositionsByTick[120])
        let third = try #require(layout.rhythmicPositionsByTick[600])

        #expect(third - second > second - first)
    }

    @Test
    func opticalExtentsPreventDenseColumnsFromOverlapping() throws {
        let layout = service.makeLayout(rhythmicColumns: [
            column(tick: 0, duration: 120, left: 2.8, right: 3.2),
            column(tick: 120, duration: 120, left: 3.4, right: 2.6),
        ])
        let first = try #require(layout.rhythmicPositionsByTick[0])
        let second = try #require(layout.rhythmicPositionsByTick[120])

        #expect(second - first >= 3.2 + 0.75 + 3.4 - 0.000_001)
    }

    @Test
    func barlineAttributeAndRhythmUseIndependentOrderedColumns() throws {
        let layout = service.makeLayout(
            rhythmicColumns: [column(tick: 480, duration: 240)],
            barlineTicks: [480],
            attributeTicks: [480]
        )
        let barline = try #require(layout.barlinePositionsByTick[480])
        let attribute = try #require(layout.attributePositionsByTick[480])
        let rhythm = try #require(layout.rhythmicPositionsByTick[480])

        #expect(barline < attribute)
        #expect(attribute < rhythm)
    }

    @Test
    func scrollSelectionTranslatesWithoutRescalingColumnDistances() throws {
        let layout = service.makeLayout(rhythmicColumns: [
            column(tick: 0, duration: 240),
            column(tick: 240, duration: 240),
            column(tick: 480, duration: 240),
        ])
        let first = try #require(layout.rhythmicPositionsByTick[0])
        let second = try #require(layout.rhythmicPositionsByTick[240])
        let width = 24.0
        let distanceAtStart = (0.5 + (second - layout.position(at: 0)) / width)
            - (0.5 + (first - layout.position(at: 0)) / width)
        let distanceAtEnd = (0.5 + (second - layout.position(at: 480)) / width)
            - (0.5 + (first - layout.position(at: 480)) / width)

        #expect(abs(distanceAtStart - distanceAtEnd) < 0.000_001)
    }

    private func column(
        tick: Int,
        duration: Int,
        left: Double = 0.8,
        right: Double = 0.8
    ) -> GrandStaffHorizontalSpacingService.RhythmicColumn {
        .init(tick: tick, durationTicks: duration, leftExtent: left, rightExtent: right)
    }
}
