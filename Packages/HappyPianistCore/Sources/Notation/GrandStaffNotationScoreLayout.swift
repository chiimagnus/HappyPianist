import Foundation
import MusicXML
import Practice

public struct GrandStaffNotationScoreInput: Equatable, Sendable {
    public let identity: PracticeSongIdentity
    public let projection: ScoreNotationProjection
    public let measureSpans: [MusicXMLMeasureSpan]
    public let facts: PracticeNotationScoreFacts
    public let attributeTimeline: MusicXMLAttributeTimeline?

    public init(
        identity: PracticeSongIdentity,
        projection: ScoreNotationProjection,
        measureSpans: [MusicXMLMeasureSpan],
        facts: PracticeNotationScoreFacts,
        attributeTimeline: MusicXMLAttributeTimeline?
    ) {
        self.identity = identity
        self.projection = projection
        self.measureSpans = measureSpans
        self.facts = facts
        self.attributeTimeline = attributeTimeline
    }
}

struct GrandStaffNotationScoreLayout: Equatable, Sendable {
    let input: GrandStaffNotationScoreInput
    let notation: GrandStaffNotationLayout
    let spacing: GrandStaffHorizontalSpacingService.Layout
    let ink: GrandStaffNotationInkLayout
}
