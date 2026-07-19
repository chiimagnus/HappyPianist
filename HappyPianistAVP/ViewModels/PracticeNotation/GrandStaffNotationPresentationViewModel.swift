import CoreGraphics

struct GrandStaffNotationPresentationViewModel {
    private let layoutService: GrandStaffNotationLayoutService
    private let viewportLayoutService: GrandStaffNotationViewportLayoutService

    init(
        layoutService: GrandStaffNotationLayoutService = GrandStaffNotationLayoutService(),
        viewportLayoutService: GrandStaffNotationViewportLayoutService = GrandStaffNotationViewportLayoutService()
    ) {
        self.layoutService = layoutService
        self.viewportLayoutService = viewportLayoutService
    }

    func makePresentation(
        size: CGSize,
        lineSpacing: CGFloat,
        projection: ScoreNotationProjection,
        overlay: ScoreNotationProjection.Overlay,
        measureSpans: [MusicXMLMeasureSpan],
        context: GrandStaffNotationContext?,
        practiceHandMode: PracticeHandMode,
        scrollTick: Double?
    ) -> GrandStaffNotationPresentation {
        let viewportWidthStaffSpaces = viewportLayoutService.horizontalStaffSpaceCapacity(
            size: size,
            lineSpacing: lineSpacing
        )
        let staffStepBounds = resolvedStaffStepBounds(
            projection: projection,
            activeTickRange: overlay.activeTickRange
        )

        let notationLayout = layoutService.makeLayout(
            projection: projection,
            overlay: overlay,
            measureSpans: measureSpans,
            context: context,
            viewportWidthStaffSpaces: viewportWidthStaffSpaces,
            scrollTick: scrollTick
        )

        let viewportLayout = viewportLayoutService.makeLayout(
            size: size,
            lineSpacing: lineSpacing,
            items: notationLayout.items,
            chords: notationLayout.chords,
            beams: notationLayout.beams,
            context: notationLayout.context,
            staffStepBounds: staffStepBounds
        )

        return GrandStaffNotationPresentation(
            notationLayout: notationLayout,
            viewportLayout: viewportLayout,
            practiceHandMode: practiceHandMode,
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
        projection: ScoreNotationProjection,
        activeTickRange: Range<Int>?
    ) -> GrandStaffNotationViewportLayoutService.StaffStepBounds {
        let sourceNotesByID = Dictionary(uniqueKeysWithValues: projection.sourceNotes.map { ($0.id, $0) })
        let occurrences = projection.performedOccurrences.filter {
            activeTickRange?.contains($0.writtenOnTick) ?? true
        }
        guard occurrences.isEmpty == false else { return .default }

        var minTrebleStep = 0
        var maxTrebleStep = 8
        var minBassStep = 0
        var maxBassStep = 8

        for occurrence in occurrences {
            guard let source = sourceNotesByID[occurrence.sourceNoteID] else { continue }
            let staffNumber = source.staff >= 2 ? 2 : 1
            guard let writtenPitch = source.writtenPitch else { continue }
            let step = layoutService.staffStep(for: writtenPitch, staffNumber: staffNumber)
            if staffNumber >= 2 {
                minBassStep = min(minBassStep, step)
                maxBassStep = max(maxBassStep, step)
            } else {
                minTrebleStep = min(minTrebleStep, step)
                maxTrebleStep = max(maxTrebleStep, step)
            }
        }

        return GrandStaffNotationViewportLayoutService.StaffStepBounds(
            minTrebleStep: minTrebleStep,
            maxTrebleStep: maxTrebleStep,
            minBassStep: minBassStep,
            maxBassStep: maxBassStep
        )
    }

}
