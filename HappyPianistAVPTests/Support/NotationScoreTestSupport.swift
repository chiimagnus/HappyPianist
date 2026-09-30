import Foundation
import MusicXML
@testable import Notation
import Practice

func makeNotationScoreFixture(
    projection: ScoreNotationProjection,
    measureSpans: [MusicXMLMeasureSpan] = []
) throws -> GrandStaffNotationScoreLayout {
    let partIDs = Set(projection.sourceNotes.map { $0.id.partID }).union(measureSpans.map(\.partID)).sorted()
    let structuralPartID = measureSpans.first?.partID ?? partIDs.first ?? "P1"
    let facts = PracticeNotationScoreFacts(
        logicalInstrument: MusicXMLLogicalInstrument(
            id: "notation-fixture", memberPartIDs: partIDs.isEmpty ? [structuralPartID] : partIDs,
            classification: .piano, evidence: []
        ),
        structuralPartID: structuralPartID
    )
    return try GrandStaffNotationScoreLayoutService().makeLayout(input: GrandStaffNotationScoreInput(
        identity: PracticeSongIdentity(songID: UUID(), scoreRevision: "notation-fixture"),
        projection: projection, measureSpans: measureSpans, facts: facts, attributeTimeline: nil
    ))
}

func makeNotationSystemFixture(
    projection: ScoreNotationProjection,
    overlay: ScoreNotationProjection.Overlay = .empty,
    measureSpans: [MusicXMLMeasureSpan] = [],
    context: GrandStaffNotationContext? = nil,
    viewportWidthStaffSpaces: Double = 36,
    scrollTick: Double? = nil
) throws -> GrandStaffNotationLayout {
    let score = try makeNotationScoreFixture(projection: projection, measureSpans: measureSpans)
    let center = score.spacing.position(at: scrollTick ?? Double(projection.performedOccurrences.first?.writtenOnTick ?? 0))
    return GrandStaffNotationSystemLayoutService().makeLayout(
        score: score,
        xRange: (center - viewportWidthStaffSpaces / 2)...(center + viewportWidthStaffSpaces / 2),
        overscan: 0.18, context: context, overlay: overlay
    )
}
