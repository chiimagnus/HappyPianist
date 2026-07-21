import Foundation
import Testing
@testable import HappyPianistAVP

@Test
func practiceSuccessSemanticsRemainDistinctInternalFacts() {
    #expect(Set(PracticeSuccessSemantic.allCases).count == 4)
    #expect(PracticeSuccessSemantic.pitchStepCompletion != .passagePerformanceAssessment)
    #expect(PracticeSuccessSemantic.referencePlaybackCompletion != .creativeDuetExchange)
}

@Test
func passageAssessmentKeepsRubricDimensionsMeasuresAndTraceableEvidence() throws {
    let event = makeAssessmentEvent()
    let observationID = UUID()
    let pitch = PerformanceAssessmentDimensionResult(
        dimension: .exactPitch,
        outcome: .correct,
        evidenceStatus: .observed,
        measurement: PerformanceAssessmentMeasurement(value: 1, unit: .ratio),
        sampleCount: 1,
        confidence: 0.9,
        evidence: [.note(
            score: .init(event: event),
            observationID: observationID,
            dimension: .pitch
        )]
    )
    let occurrence = PracticeMeasureOccurrenceID(
        sourceMeasureID: .init(partID: "P1", sourceMeasureIndex: 0, sourceNumberToken: "1"),
        occurrenceIndex: 0
    )
    let assessment = PassagePerformanceAssessment(
        planID: .init(rawValue: "plan"),
        sourceGeneration: 7,
        tickRange: 0 ..< 960,
        rubricVersion: .initial,
        dimensions: [pitch],
        measures: [.init(occurrenceID: occurrence, tickRange: 0 ..< 960, dimensions: [pitch])]
    )

    #expect(assessment.sourceGeneration == 7)
    #expect(assessment.rubricVersion == .initial)
    #expect(assessment.dimensions == [pitch])
    #expect(assessment.measures.first?.occurrenceID == occurrence)
    #expect(pitch.evidence == [.note(
        score: .init(event: event),
        observationID: observationID,
        dimension: .pitch
    )])
}

@Test
func dimensionResultSanitizesOnlyNumericBoundaries() {
    let result = PerformanceAssessmentDimensionResult(
        dimension: .onset,
        outcome: .insufficientEvidence,
        evidenceStatus: .insufficient,
        sampleCount: -2,
        confidence: 2,
        evidence: []
    )

    #expect(result.sampleCount == 0)
    #expect(result.confidence == 1)
    #expect(PerformanceAssessmentMeasurement(value: .infinity, unit: .seconds) == nil)
}

@Test
func assessmentKeepsUnknownAndInsufficientSeparateFromIncorrect() {
    let unknown = PerformanceAssessmentDimensionResult(
        dimension: .voicing,
        outcome: .unknown,
        evidenceStatus: .notObserved,
        sampleCount: 0,
        evidence: []
    )
    let insufficient = PerformanceAssessmentDimensionResult(
        dimension: .onset,
        outcome: .insufficientEvidence,
        evidenceStatus: .insufficient,
        sampleCount: 1,
        evidence: []
    )

    #expect(unknown.outcome == .unknown)
    #expect(insufficient.outcome == .insufficientEvidence)
    #expect(unknown.outcome != .incorrect)
    #expect(insufficient.outcome != .incorrect)
}

private func makeAssessmentEvent() -> ScorePerformanceNoteEvent {
    let sourceID = MusicXMLSourceNoteID(
        partID: "P1",
        sourceMeasureIndex: 0,
        sourceMeasureNumberToken: "1",
        staff: 1,
        voice: 1,
        sourceOrdinal: 0
    )
    let performedID = MusicXMLPerformedNoteID(sourceID: sourceID, occurrenceIndex: 0)
    return ScorePerformanceNoteEvent(
        id: .init(performedNoteID: performedID, generatedOrdinal: nil),
        sourceNoteID: sourceID,
        performedNoteID: performedID,
        contributingSourceNoteIDs: [sourceID],
        contributingPerformedNoteIDs: [performedID],
        purpose: .source,
        writtenOnTick: 0,
        writtenOffTick: 480,
        performedOnTick: 0,
        performedOffTick: 480,
        writtenPitch: nil,
        midiNote: 60,
        velocityResolution: .init(
            baseVelocity: 90,
            curveVelocity: nil,
            articulationDelta: 0,
            unclampedVelocity: 90,
            velocity: 90
        ),
        staff: 1,
        voice: 1,
        handAssignment: .unknown,
        fingerings: [],
        timingProvenance: []
    )
}
