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

@Test
func candidateEngineUsesCapabilitiesRangeGenerationAndPlanResolution() throws {
    let sourceID = makeAlignmentSourceID(ordinal: 0)
    let event = makeAlignmentEvent(sourceID: sourceID, occurrenceIndex: 0)
    let plan = makeAlignmentPlan(noteEvents: [event], ticksPerQuarter: 960)
    let exact = makeAlignmentObservation(generation: 9, note: 60, seconds: 0)
    let wrong = makeAlignmentObservation(generation: 9, note: 61, seconds: 0)
    let stale = makeAlignmentObservation(generation: 8, note: 60, seconds: 0)

    let snapshots = PerformanceAlignmentEngine().candidates(
        plan: plan,
        observations: [exact, wrong, stale],
        performanceStart: .init(seconds: 0),
        activeTickRange: 0 ..< 960,
        generation: 9
    )

    #expect(snapshots[0].candidates.map(\.score.eventID) == [event.id])
    #expect(snapshots[1].noCandidateReason == .noPitchCandidate)
    #expect(snapshots[2].noCandidateReason == .staleGeneration)
}

@Test
func recordedTakeAlignerRebasesV2ObservationsAndKeepsLegacyCapabilityUnknown() throws {
    let sourceID = makeAlignmentSourceID(ordinal: 0)
    let plan = makeAlignmentPlan(noteEvents: [makeAlignmentEvent(sourceID: sourceID, occurrenceIndex: 0)])
    let observation = makeAlignmentObservation(generation: 4, note: 60, seconds: 40)
    let v2 = RecordingTake(
        name: "v2",
        events: [.init(time: 0, kind: .noteOn(midi: 60, velocity: 80), observation: observation)]
    )
    let legacy = RecordingTake(
        name: "legacy",
        events: [.init(time: 0, kind: .noteOn(midi: 61, velocity: 80))]
    )

    let aligner = RecordedTakeAligner()
    #expect(aligner.candidateSnapshots(take: v2, plan: plan).first?.candidates.count == 1)
    #expect(aligner.candidateSnapshots(take: legacy, plan: plan).first?.candidates.count == 1)
}

@Test
func alignmentSeparatesExactPitchOnsetChordSpreadExtraAndMissing() {
    let c = makeAlignmentEvent(sourceID: makeAlignmentSourceID(ordinal: 0), occurrenceIndex: 0)
    let e = makeAlignmentEvent(
        sourceID: makeAlignmentSourceID(ordinal: 1),
        occurrenceIndex: 0,
        midiNote: 64
    )
    let missing = makeAlignmentEvent(
        sourceID: makeAlignmentSourceID(ordinal: 2),
        occurrenceIndex: 0,
        midiNote: 67,
        onTick: 480
    )
    let plan = makeAlignmentPlan(noteEvents: [c, e, missing])
    let observations = [
        makeAlignmentObservation(generation: 2, note: 60, seconds: 0),
        makeAlignmentObservation(generation: 2, note: 64, seconds: 0.08),
        makeAlignmentObservation(generation: 2, note: 61, seconds: 0.2),
    ]

    let result = PerformanceAlignmentEngine().align(
        plan: plan,
        observations: observations,
        performanceStart: .init(seconds: 0),
        generation: 2
    )

    let aligned = result.links.compactMap { link -> [PerformanceAlignmentEvidence]? in
        guard case let .aligned(_, _, evidence) = link else { return nil }
        return evidence
    }
    #expect(aligned.count == 2)
    #expect(aligned.allSatisfy { evidence in
        evidence.contains { $0.dimension == .pitch && $0.cost == 0 }
            && evidence.contains { $0.dimension == .chordSpread && $0.deviationSeconds == 0.08 }
    })
    #expect(result.links.filter { if case .extra = $0 { true } else { false } }.count == 1)
    #expect(result.links.filter { if case .missing = $0 { true } else { false } }.count == 1)
}

@Test
func releaseDurationAndControllerEvidenceRespectCapabilities() throws {
    let event = makeAlignmentEvent(sourceID: makeAlignmentSourceID(ordinal: 0), occurrenceIndex: 0)
    let controller = ScorePerformanceControllerEvent(
        sourceDirectionID: nil,
        performedOccurrenceIndex: 0,
        tick: 0,
        controllerNumber: 64,
        value: 80,
        outputCapabilityRequirement: .continuousControlChange
    )
    let plan = makeAlignmentPlan(noteEvents: [event], controllerEvents: [controller])
    let noteOn = makeAlignmentObservation(generation: 3, note: 60, seconds: 0)
    let noteOff = makeAlignmentObservation(
        generation: 3,
        note: 60,
        seconds: 0.4,
        event: .noteOff(note: 60, releaseVelocity: nil)
    )
    let control = makeAlignmentObservation(
        generation: 3,
        note: 0,
        seconds: 0.05,
        event: .controller(.controlChange(number: 64, value: .init(midi1: 72)))
    )

    let result = PerformanceAlignmentEngine().align(
        plan: plan,
        observations: [noteOn, noteOff, control],
        performanceStart: .init(seconds: 0),
        generation: 3
    )

    let evidence = try #require(result.links.compactMap { link -> [PerformanceAlignmentEvidence]? in
        guard case let .aligned(_, _, evidence) = link else { return nil }
        return evidence
    }.first)
    #expect(evidence.contains {
        $0.dimension == .duration && abs(($0.deviationSeconds ?? 0) + 0.1) < 0.000_001
    })
    #expect(result.controllerLinks.count == 1)
    guard case let .aligned(_, _, timeDeviation, valueDeviation) = result.controllerLinks[0] else {
        Issue.record("Expected aligned controller")
        return
    }
    #expect(timeDeviation == 0.05)
    #expect(abs(valueDeviation - 8.0 / 127.0) < 0.000_001)
}

@Test
func unavailableReleaseAndControllerProduceNotObserved() throws {
    let unavailable = PerformanceInputCapabilities(
        pitch: .observed,
        onset: .observed,
        release: .unavailable,
        velocity: .unavailable,
        controllers: .unavailable,
        polyphony: .observed,
        hand: .unavailable,
        finger: .unavailable,
        position: .unavailable,
        confidence: .unavailable
    )
    let event = makeAlignmentEvent(sourceID: makeAlignmentSourceID(ordinal: 0), occurrenceIndex: 0)
    let controller = ScorePerformanceControllerEvent(
        sourceDirectionID: nil,
        performedOccurrenceIndex: 0,
        tick: 0,
        controllerNumber: 64,
        value: 100,
        outputCapabilityRequirement: .continuousControlChange
    )
    let plan = makeAlignmentPlan(noteEvents: [event], controllerEvents: [controller])
    let note = makeAlignmentObservation(
        generation: 1,
        note: 60,
        seconds: 0,
        capabilities: unavailable
    )
    let result = PerformanceAlignmentEngine().align(
        plan: plan,
        observations: [note],
        performanceStart: .init(seconds: 0)
    )

    let evidence = try #require(result.links.compactMap { link -> [PerformanceAlignmentEvidence]? in
        guard case let .aligned(_, _, evidence) = link else { return nil }
        return evidence
    }.first)
    #expect(evidence.contains { $0.dimension == .release && $0.status == .notObserved })
    #expect(result.controllerLinks == [.notObserved(score: .init(event: controller))])
}

private func makeAlignmentObservation(
    generation: UInt64,
    note: Int = 60,
    seconds: TimeInterval = 12,
    event: PerformanceObservation.Event? = nil,
    capabilities: PerformanceInputCapabilities? = nil
) -> PerformanceObservation {
    PerformanceObservation(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!,
        source: .init(
            kind: .midi1,
            id: "midi:test",
            generation: generation,
            capabilities: capabilities
        ),
        timing: PerformanceClockReading(
            host: .init(seconds: seconds + 0.1),
            source: nil,
            correctedHost: .init(seconds: seconds),
            mapping: nil,
            provenance: .latencyEstimate
        ),
        event: event ?? .noteOn(note: note, velocity: .init(midi1: 90))
    )
}

private func makeAlignmentSourceID(ordinal: Int) -> MusicXMLSourceNoteID {
    MusicXMLSourceNoteID(
        partID: "P1",
        sourceMeasureIndex: 0,
        sourceMeasureNumberToken: "1",
        staff: 1,
        voice: 1,
        sourceOrdinal: ordinal
    )
}

private func makeAlignmentPlan(
    noteEvents: [ScorePerformanceNoteEvent],
    ticksPerQuarter: Int = 480,
    controllerEvents: [ScorePerformanceControllerEvent] = []
) -> ScorePerformancePlan {
    ScorePerformancePlan(
        id: .init(rawValue: "alignment-plan"),
        sourceScoreIdentity: .init(
            songID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            scoreRevision: "revision",
            logicalInstrumentID: "piano"
        ),
        order: .init(requested: .performed, applied: .performed),
        resolution: .init(ticksPerQuarter: ticksPerQuarter),
        noteEvents: noteEvents,
        tempoEvents: [],
        controllerEvents: controllerEvents,
        annotations: [],
        approximations: []
    )
}

private func makeAlignmentEvent(
    sourceID: MusicXMLSourceNoteID,
    occurrenceIndex: Int,
    midiNote: Int = 60,
    onTick: Int = 0
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
        writtenOnTick: onTick,
        writtenOffTick: onTick + 480,
        performedOnTick: onTick,
        performedOffTick: onTick + 480,
        writtenPitch: .init(step: "C", octave: 4, alter: 0, accidentalToken: nil),
        midiNote: midiNote,
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
