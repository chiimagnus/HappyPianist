import CoreGraphics
import MusicXML
import Practice

struct GrandStaffNotationPresentationViewModel {
    private let viewportLayoutService: GrandStaffNotationViewportLayoutService

    init(
        viewportLayoutService: GrandStaffNotationViewportLayoutService = GrandStaffNotationViewportLayoutService()
    ) {
        self.viewportLayoutService = viewportLayoutService
    }

    func makePresentation(
        size: CGSize,
        lineSpacing: CGFloat,
        score: GrandStaffNotationScoreLayout,
        overlay: ScoreNotationProjection.Overlay,
        context: GrandStaffNotationContext?,
        practiceHandMode: PracticeHandMode,
        scrollTick: Double?
    ) -> GrandStaffNotationPresentation {
        let viewportWidthStaffSpaces = viewportLayoutService.horizontalStaffSpaceCapacity(
            size: size,
            lineSpacing: lineSpacing
        )
        let centerTick = scrollTick ?? Double(score.input.projection.performedOccurrences.first?.writtenOnTick ?? 0)
        let center = score.spacing.position(at: centerTick)
        let notationLayout = GrandStaffNotationSystemLayoutService().makeLayout(
            score: score,
            xRange: (center - viewportWidthStaffSpaces / 2)...(center + viewportWidthStaffSpaces / 2),
            overscan: 0.18,
            context: context,
            overlay: overlay
        )
        let staffStepBounds = resolvedStaffStepBounds(score: score)

        let viewportLayout = viewportLayoutService.makeLayout(
            size: size,
            lineSpacing: lineSpacing,
            items: notationLayout.items,
            chords: notationLayout.chords,
            beams: notationLayout.beams,
            marks: notationLayout.marks,
            context: notationLayout.context,
            staffStepBounds: staffStepBounds
        )

        return GrandStaffNotationPresentation(
            notationLayout: notationLayout,
            viewportLayout: viewportLayout,
            practiceHandMode: practiceHandMode,
            activeTickRange: overlay.activeTickRange,
            chordsByID: Dictionary(uniqueKeysWithValues: notationLayout.chords.map { ($0.id, $0) }),
            itemsByChordID: Dictionary(grouping: notationLayout.items, by: { $0.chordID ?? "" }),
            beamedChordIDs: Set(notationLayout.beams.flatMap(\.chordIDs)),
            defaultScrollAnchorY: resolvedDefaultScrollAnchorY(layout: viewportLayout)
        )
    }

    private func resolvedDefaultScrollAnchorY(
        layout: GrandStaffNotationViewportLayoutService.Layout
    ) -> CGFloat {
        let trebleTop = layout.trebleTopLineY + layout.canvasYOffset
        let bassBottom = layout.bassBottomLineY + layout.canvasYOffset
        let center = (trebleTop + bassBottom) / 2
        return min(max(0, center), layout.requiredHeight)
    }

    private func resolvedStaffStepBounds(
        score: GrandStaffNotationScoreLayout
    ) -> GrandStaffNotationViewportLayoutService.StaffStepBounds {
        let treble = score.notation.items.filter { $0.staffNumber == 1 }.map(\.staffStep)
        let bass = score.notation.items.filter { $0.staffNumber == 2 }.map(\.staffStep)
        return GrandStaffNotationViewportLayoutService.StaffStepBounds(
            minTrebleStep: min(0, treble.min() ?? 0),
            maxTrebleStep: max(8, treble.max() ?? 8),
            minBassStep: min(0, bass.min() ?? 0),
            maxBassStep: max(8, bass.max() ?? 8)
        )
    }
}
