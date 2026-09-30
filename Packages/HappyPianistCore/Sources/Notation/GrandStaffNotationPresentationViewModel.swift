import Practice

struct GrandStaffNotationPresentationViewModel {
    func makePresentation(system: GrandStaffNotationPagePlan.System, staffSpace: Double, projection: ScoreNotationProjection, overlay: ScoreNotationProjection.Overlay, practiceHandMode: PracticeHandMode) -> GrandStaffNotationPresentation {
        let canvas = GrandStaffNotationSystemCanvasLayoutService().makeLayout(system: system, staffSpace: staffSpace)
        let original = system.notation
        let highlighted = Set(projection.performedOccurrences.filter { $0.performanceEventIDs.contains(where: overlay.activeEventIDs.contains) }.map { $0.id.description })
        let notation = GrandStaffNotationLayout(
            items: original.items.map { value in var result = value; result.isHighlighted = highlighted.contains(value.id); return result },
            chords: original.chords,
            rests: original.rests.map { value in var result = value; result.isHighlighted = highlighted.contains(value.id); return result },
            ties: original.ties, slurs: original.slurs, tuplets: original.tuplets, barlines: original.barlines, beams: original.beams, ledgerLines: original.ledgerLines, marks: original.marks, attributeChanges: original.attributeChanges, context: original.context, spannerAnchors: original.spannerAnchors
        )
        return .init(notationLayout: notation, canvasLayout: canvas, practiceHandMode: practiceHandMode, activeTickRange: overlay.activeTickRange, chordsByID: Dictionary(uniqueKeysWithValues: notation.chords.map { ($0.id, $0) }), itemsByChordID: Dictionary(grouping: notation.items, by: { $0.chordID ?? "" }), beamedChordIDs: Set(notation.beams.flatMap(\.chordIDs)))
    }
}
