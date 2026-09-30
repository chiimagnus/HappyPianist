import Foundation
import MusicXML
@testable import Notation
import Practice

func makeNotationScoreFixture(
    projection: ScoreNotationProjection,
    measureSpans: [MusicXMLMeasureSpan] = [],
    attributeTimeline: MusicXMLAttributeTimeline? = nil
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
        projection: projection, measureSpans: measureSpans, facts: facts, attributeTimeline: attributeTimeline
    ))
}

func makeNotationSystemFixture(
    projection: ScoreNotationProjection,
    overlay: ScoreNotationProjection.Overlay = .empty,
    measureSpans: [MusicXMLMeasureSpan] = [],
    context: GrandStaffNotationContext? = nil,
    sliceWidthStaffSpaces: Double = 36,
    sliceCenterTick: Double? = nil
) throws -> GrandStaffNotationLayout {
    let score = try makeNotationScoreFixture(projection: projection, measureSpans: measureSpans)
    let center = score.spacing.position(at: sliceCenterTick ?? Double(projection.performedOccurrences.first?.writtenOnTick ?? 0))
    return GrandStaffNotationSystemLayoutService().makeLayout(
        score: score,
        xRange: (center - sliceWidthStaffSpaces / 2)...(center + sliceWidthStaffSpaces / 2),
        context: context, overlay: overlay
    )
}
