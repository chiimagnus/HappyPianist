import Foundation
@testable import HappyPianistAVP
import Testing

@Test
func alignmentReferencesKeepPlanSourceOccurrenceAndObservationIdentity() throws {
    let sourceID = MusicXMLSourceNoteID(
        partID: "P1",
        sourceMeasureIndex: 2,
        sourceMeasureNumberToken: "3",
        staff: 2,
        voice: 1,
        sourceOrdinal: 4
    )
    let event = makeAlignmentEvent(sourceID: sourceID, occurrenceIndex: 3)
    let observation = makeAlignmentObservation(generation: 7)

    let scoreReference = PerformanceAlignmentScoreReference(event: event)
    let observationReference = PerformanceAlignmentObservationReference(observation: observation)
    let alignment = PerformanceAlignment(
        planID: ScorePerformancePlanID(rawValue: "plan"),
        sourceGeneration: 7,
        links: [.aligned(
            score: scoreReference,
            observation: observationReference,
            evidence: [.init(dimension: .pitch, status: .observed, cost: 0)]
        )]
    )

    #expect(scoreReference.sourceNoteID == sourceID)
    #expect(scoreReference.performedOccurrenceIndex == 3)
    #expect(observationReference.observationID == observation.id)
    #expect(observationReference.correctedTime.seconds == 12)
    #expect(try JSONDecoder().decode(
        PerformanceAlignment.self,
        from: JSONEncoder().encode(alignment)
    ) == alignment)
}

@Test
func alignmentEvidenceRejectsNonFiniteValuesWithoutInventingEvidence() {
    let evidence = PerformanceAlignmentEvidence(
        dimension: .release,
        status: .notObserved,
        cost: .infinity,
        deviationSeconds: .nan
    )

    #expect(evidence.cost == nil)
    #expect(evidence.deviationSeconds == nil)
}

private func makeAlignmentObservation(generation: UInt64) -> PerformanceObservation {
    PerformanceObservation(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!,
        source: .init(kind: .midi1, id: "midi:test", generation: generation),
        timing: PerformanceClockReading(
            host: .init(seconds: 12.1),
            source: nil,
            correctedHost: .init(seconds: 12),
            mapping: nil,
            provenance: .latencyEstimate
        ),
        event: .noteOn(note: 60, velocity: .init(midi1: 90))
    )
}

private func makeAlignmentEvent(
    sourceID: MusicXMLSourceNoteID,
    occurrenceIndex: Int
) -> ScorePerformanceNoteEvent {
    let performedID = MusicXMLPerformedNoteID(
        sourceID: sourceID,
        occurrenceIndex: occurrenceIndex
    )
    return ScorePerformanceNoteEvent(
        id: ScorePerformanceNoteEventID(performedNoteID: performedID, generatedOrdinal: nil),
        sourceNoteID: sourceID,
        performedNoteID: performedID,
        contributingSourceNoteIDs: [sourceID],
        contributingPerformedNoteIDs: [performedID],
        purpose: .source,
        writtenOnTick: 0,
        writtenOffTick: 480,
        performedOnTick: 0,
        performedOffTick: 480,
        writtenPitch: .init(step: "C", octave: 4, alter: 0, accidentalToken: nil),
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
        handAssignment: .init(hand: .right, provenance: .score),
        fingerings: [],
        timingProvenance: []
    )
}
