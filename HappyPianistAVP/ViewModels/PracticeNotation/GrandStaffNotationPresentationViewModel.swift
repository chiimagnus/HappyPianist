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
        measureSpans: [MusicXMLMeasureSpan],
        context: GrandStaffNotationContext?,
        practiceHandMode: PracticeHandMode,
        tickRange: Range<Int>?,
        scrollTick: Double?
    ) -> GrandStaffNotationPresentation {
        let contentWidth = resolvedContentWidth(for: size, lineSpacing: lineSpacing)
        let halfWindowTicks = resolvedHalfWindowTicks(contentWidth: contentWidth, lineSpacing: lineSpacing)
        let staffStepBounds = resolvedStaffStepBounds(
            projection: projection,
            tickRange: tickRange
        )

        let notationLayout = layoutService.makeLayout(
            projection: projection,
            measureSpans: measureSpans,
            context: context,
            tickRange: tickRange,
            halfWindowTicks: halfWindowTicks,
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
            ledgerStepsByItemID: Dictionary(
                uniqueKeysWithValues: notationLayout.items.map { item in
                    (item.id, layoutService.ledgerStaffSteps(for: item.staffStep))
                }
            ),
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

    private func resolvedContentWidth(for size: CGSize, lineSpacing: CGFloat) -> CGFloat {
        let contextMinX: CGFloat = 4
        let contextWidth: CGFloat = lineSpacing * 7.0
        let contentMinX = contextMinX + contextWidth
        let contentMaxX = min(size.width - 18, size.width * 0.96)
        return max(1, contentMaxX - contentMinX)
    }

    private func resolvedHalfWindowTicks(contentWidth: CGFloat, lineSpacing: CGFloat) -> Int {
        let pointsPerQuarter = max(1, lineSpacing * 6.0)
        let ticksPerPoint = Double(MusicXMLTempoMap.ticksPerQuarter) / Double(pointsPerQuarter)
        let half = Int((Double(contentWidth) * ticksPerPoint) / 2.0)
        return max(MusicXMLTempoMap.ticksPerQuarter, half)
    }

    private func resolvedStaffStepBounds(
        projection: ScoreNotationProjection,
        tickRange: Range<Int>?
    ) -> GrandStaffNotationViewportLayoutService.StaffStepBounds {
        let sourceNotesByID = Dictionary(grouping: projection.sourceNotes, by: \.id)
            .compactMapValues { notes in notes.count == 1 ? notes[0] : nil }
        let occurrences = projection.performedOccurrences.filter {
            tickRange?.contains($0.writtenOnTick) ?? true
        }
        guard occurrences.isEmpty == false else { return .default }

        var minTrebleStep = 0
        var maxTrebleStep = 8
        var minBassStep = 0
        var maxBassStep = 8

        for occurrence in occurrences {
            guard let source = sourceNotesByID[occurrence.sourceNoteID] else { continue }
            let staffNumber = source.staff >= 2 ? 2 : 1
            let step = layoutService.staffStep(
                for: source.midiNote ?? occurrence.midiNote,
                staffNumber: staffNumber
            )
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
