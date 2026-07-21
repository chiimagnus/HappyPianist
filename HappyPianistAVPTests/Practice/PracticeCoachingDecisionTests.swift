@testable import HappyPianistAVP
import Testing

@Test
func performanceDimensionsMapToMusicalIssueTaxonomy() {
    let expected: [PerformanceAssessmentDimension: MusicalIssueKind] = [
        .exactPitch: .pitch,
        .extraNotes: .pitch,
        .missingNotes: .pitch,
        .onset: .onset,
        .tempoRelativeTiming: .tempo,
        .chordSpread: .chordSpread,
        .duration: .duration,
        .release: .duration,
        .articulation: .articulation,
        .velocity: .dynamicContour,
        .dynamicContour: .dynamicContour,
        .voicing: .voicing,
        .pedalTiming: .pedal,
        .pedalValue: .pedal,
        .tempoContinuity: .tempo,
        .phraseContinuity: .phrase,
    ]

    #expect(expected.count == PerformanceAssessmentDimension.allCases.count)
    for dimension in PerformanceAssessmentDimension.allCases {
        #expect(dimension.musicalIssueKind == expected[dimension])
    }
}

@Test
func musicalIssueRetainsAssessmentEvidenceAndBoundsConfidence() {
    let dimension = PerformanceAssessmentDimensionResult(
        dimension: .onset,
        outcome: .incorrect,
        evidenceStatus: .observed,
        measurement: PerformanceAssessmentMeasurement(value: 0.12, unit: .seconds),
        sampleCount: 3,
        confidence: 0.8,
        evidence: []
    )
    let provenance = MusicalIssueProvenance(
        planID: ScorePerformancePlanID(rawValue: "plan"),
        sourceGeneration: 4,
        rubricVersion: .capabilityAware
    )

    let issue = MusicalIssue(
        kind: .onset,
        scoreRange: 480 ..< 960,
        dimensionResults: [dimension],
        confidence: 1.2,
        provenance: provenance
    )

    #expect(issue.scoreRange == 480 ..< 960)
    #expect(issue.dimensionResults == [dimension])
    #expect(issue.confidence == 1)
    #expect(issue.provenance == provenance)

    let unknownConfidence = MusicalIssue(
        kind: .evidence,
        scoreRange: 480 ..< 960,
        dimensionResults: [dimension],
        confidence: .infinity,
        provenance: provenance
    )
    #expect(unknownConfidence.confidence == nil)
}
