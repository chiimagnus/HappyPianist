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

@Test
func assessmentCalculatesPitchOnsetAndTempoRelativeTimingFromAlignmentEvidence() throws {
    let event = makeAssessmentEvent()
    let plan = makeAssessmentPlan(events: [event])
    let observation = makeAssessmentObservation(time: 0.04)
    let alignment = PerformanceAlignment(
        planID: plan.id,
        sourceGeneration: 7,
        links: [makeAlignedLink(event: event, observation: observation, onsetDeviation: 0.04)]
    )

    let assessment = try #require(PerformanceAssessmentService().assess(plan: plan, alignment: alignment))
    let pitch = try assessmentResult(.exactPitch, in: assessment)
    let onset = try assessmentResult(.onset, in: assessment)
    let relative = try assessmentResult(.tempoRelativeTiming, in: assessment)

    #expect(pitch.outcome == .correct)
    #expect(pitch.measurement?.value == 1)
    #expect(onset.outcome == .correct)
    #expect(abs((onset.measurement?.value ?? 0) - 0.04) < 0.000_001)
    #expect(relative.outcome == .correct)
    #expect(abs((relative.measurement?.value ?? 0) - 0.08) < 0.000_001)
    #expect(onset.sampleCount == 1)
    #expect(onset.confidence == 1)
    #expect(assessment.measures.count == 1)
}

@Test
func assessmentKeepsExtraAndMissingNotesAsSeparateIncorrectFacts() throws {
    let event = makeAssessmentEvent()
    let plan = makeAssessmentPlan(events: [event])
    let extraObservation = makeAssessmentObservation(id: UUID(), time: 0.1, note: 62)
    let alignment = PerformanceAlignment(
        planID: plan.id,
        sourceGeneration: 7,
        links: [
            .missing(
                score: .init(event: event),
                evidence: [.init(dimension: .pitch, status: .observed, cost: 5)]
            ),
            .extra(
                observation: .init(observation: extraObservation),
                evidence: [.init(dimension: .pitch, status: .observed, cost: 5)]
            ),
        ]
    )

    let assessment = try #require(PerformanceAssessmentService().assess(plan: plan, alignment: alignment))
    let extra = try assessmentResult(.extraNotes, in: assessment)
    let missing = try assessmentResult(.missingNotes, in: assessment)

    #expect(extra.outcome == .incorrect)
    #expect(extra.measurement?.value == 1)
    #expect(extra.sampleCount == 1)
    #expect(missing.outcome == .incorrect)
    #expect(missing.measurement?.value == 1)
    #expect(missing.sampleCount == 1)
}

@Test
func assessmentPreservesEarlyAndLateOnsetDirection() throws {
    for deviation in [-0.12, 0.12] {
        let event = makeAssessmentEvent()
        let plan = makeAssessmentPlan(events: [event])
        let observation = makeAssessmentObservation(time: max(0, deviation))
        let alignment = PerformanceAlignment(
            planID: plan.id,
            sourceGeneration: 7,
            links: [makeAlignedLink(event: event, observation: observation, onsetDeviation: deviation)]
        )

        let assessment = try #require(PerformanceAssessmentService().assess(plan: plan, alignment: alignment))
        let onset = try assessmentResult(.onset, in: assessment)
        let relative = try assessmentResult(.tempoRelativeTiming, in: assessment)

        #expect(onset.outcome == .incorrect)
        #expect(abs((onset.measurement?.value ?? 0) - deviation) < 0.000_001)
        #expect(relative.outcome == .incorrect)
        #expect((relative.measurement?.value ?? 0).sign == deviation.sign)
    }
}

@Test
func assessmentCountsOneChordSpreadSamplePerCompleteChord() throws {
    let events = [
        makeAssessmentEvent(ordinal: 0, midiNote: 60),
        makeAssessmentEvent(ordinal: 1, midiNote: 64),
    ]
    let plan = makeAssessmentPlan(events: events)
    let links = events.enumerated().map { index, event in
        makeAlignedLink(
            event: event,
            observation: makeAssessmentObservation(time: Double(index) * 0.12, note: event.midiNote),
            onsetDeviation: Double(index) * 0.12,
            chordSpread: 0.12
        )
    }
    let alignment = PerformanceAlignment(planID: plan.id, sourceGeneration: 7, links: links)

    let assessment = try #require(PerformanceAssessmentService().assess(plan: plan, alignment: alignment))
    let chordSpread = try assessmentResult(.chordSpread, in: assessment)

    #expect(chordSpread.outcome == .incorrect)
    #expect(chordSpread.sampleCount == 1)
    #expect(abs((chordSpread.measurement?.value ?? 0) - 0.12) < 0.000_001)
    #expect(chordSpread.evidence.count == 2)
}

@Test
func assessmentUsesGracePlanTimingAndDoesNotTreatArpeggioAsChordSpread() throws {
    let arpeggio = ScorePerformanceProvenance(kind: .arpeggio, sourceIdentity: nil, detail: "up")
    let grace = ScorePerformanceProvenance(kind: .grace, sourceIdentity: nil, detail: "acciaccatura")
    let events = [
        makeAssessmentEvent(ordinal: 0, midiNote: 60, timingProvenance: [arpeggio]),
        makeAssessmentEvent(ordinal: 1, midiNote: 64, timingProvenance: [arpeggio]),
        makeAssessmentEvent(
            ordinal: 2,
            midiNote: 62,
            onTick: 480,
            offTick: 600,
            timingProvenance: [grace]
        ),
    ]
    let plan = makeAssessmentPlan(events: events)
    let links = events.map { event in
        makeAlignedLink(
            event: event,
            observation: makeAssessmentObservation(
                time: event.performedOnTick == 0 ? 0.02 : 0.53,
                note: event.midiNote
            ),
            onsetDeviation: event.performedOnTick == 0 ? 0.02 : 0.03
        )
    }
    let alignment = PerformanceAlignment(planID: plan.id, sourceGeneration: 7, links: links)

    let assessment = try #require(PerformanceAssessmentService().assess(plan: plan, alignment: alignment))
    let onset = try assessmentResult(.onset, in: assessment)
    let chordSpread = try assessmentResult(.chordSpread, in: assessment)

    #expect(onset.sampleCount == 3)
    #expect(onset.outcome == .correct)
    #expect(chordSpread.outcome == .unknown)
    #expect(chordSpread.evidenceStatus == .notObserved)
}

@Test
func ambiguousAlignmentProducesInsufficientEvidenceInsteadOfWrongNotes() throws {
    let event = makeAssessmentEvent()
    let plan = makeAssessmentPlan(events: [event])
    let observation = makeAssessmentObservation(time: 0.05)
    let candidate = PerformanceAlignmentCandidate(
        score: .init(event: event),
        totalCost: 0.05,
        evidence: [
            .init(dimension: .pitch, status: .observed, cost: 0),
            .init(dimension: .onset, status: .observed, cost: 0.05, deviationSeconds: 0.05),
        ]
    )
    let alignment = PerformanceAlignment(
        planID: plan.id,
        sourceGeneration: 7,
        links: [.ambiguous(observation: .init(observation: observation), candidates: [candidate])]
    )

    let assessment = try #require(PerformanceAssessmentService().assess(plan: plan, alignment: alignment))
    let pitch = try assessmentResult(.exactPitch, in: assessment)
    let onset = try assessmentResult(.onset, in: assessment)

    #expect(pitch.outcome == .insufficientEvidence)
    #expect(pitch.evidenceStatus == .insufficient)
    #expect(pitch.sampleCount == 0)
    #expect(onset.outcome == .insufficientEvidence)
    #expect(onset.outcome != .incorrect)
}

@Test
func analyzerImmediatelyPublishesAssessmentFromItsFinishedAlignment() async throws {
    let event = makeAssessmentEvent()
    let plan = makeAssessmentPlan(events: [event])
    let analyzer = PracticePerformanceAnalyzer()
    let start = PerformanceMonotonicInstant(seconds: 5)

    await analyzer.configure(plan: plan, activeTickRange: nil)
    await analyzer.beginRound(at: start)
    await analyzer.record(makeAssessmentObservation(time: 5))
    let snapshot = await analyzer.finishRound()

    let assessment = try #require(snapshot.assessment)
    #expect(snapshot.alignment != nil)
    #expect(try assessmentResult(.exactPitch, in: assessment).outcome == .correct)
}

private func makeAssessmentEvent(
    ordinal: Int = 0,
    midiNote: Int = 60,
    onTick: Int = 0,
    offTick: Int = 480,
    timingProvenance: [ScorePerformanceProvenance] = []
) -> ScorePerformanceNoteEvent {
    let sourceID = MusicXMLSourceNoteID(
        partID: "P1",
        sourceMeasureIndex: 0,
        sourceMeasureNumberToken: "1",
        staff: 1,
        voice: 1,
        sourceOrdinal: ordinal
    )
    let performedID = MusicXMLPerformedNoteID(sourceID: sourceID, occurrenceIndex: 0)
    return ScorePerformanceNoteEvent(
        id: .init(performedNoteID: performedID, generatedOrdinal: nil),
        sourceNoteID: sourceID,
        performedNoteID: performedID,
        contributingSourceNoteIDs: [sourceID],
        contributingPerformedNoteIDs: [performedID],
        purpose: .source,
        writtenOnTick: onTick,
        writtenOffTick: offTick,
        performedOnTick: onTick,
        performedOffTick: offTick,
        writtenPitch: nil,
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
        handAssignment: .unknown,
        fingerings: [],
        timingProvenance: timingProvenance
    )
}

private func makeAssessmentPlan(events: [ScorePerformanceNoteEvent]) -> ScorePerformancePlan {
    ScorePerformancePlan(
        id: .init(rawValue: "assessment-plan"),
        sourceScoreIdentity: .init(
            songID: UUID(),
            scoreRevision: "test",
            logicalInstrumentID: "piano"
        ),
        order: .init(requested: .written, applied: .written),
        resolution: .init(ticksPerQuarter: 480),
        noteEvents: events,
        tempoEvents: [.init(
            sourceDirectionID: nil,
            performedOccurrenceIndex: 0,
            tick: 0,
            quarterBPM: 120,
            endTick: nil,
            endQuarterBPM: nil
        )],
        controllerEvents: [],
        annotations: [],
        approximations: []
    )
}

private func makeAssessmentObservation(
    id: UUID = UUID(),
    time: TimeInterval,
    note: Int = 60
) -> PerformanceObservation {
    let instant = PerformanceMonotonicInstant(seconds: time)
    return PerformanceObservation(
        id: id,
        source: .init(kind: .midi1, id: "assessment-midi", generation: 7),
        timing: .init(
            host: instant,
            source: nil,
            correctedHost: instant,
            mapping: nil,
            provenance: .hostOnly
        ),
        event: .noteOn(note: note, velocity: .init(midi1: 90))
    )
}

private func makeAlignedLink(
    event: ScorePerformanceNoteEvent,
    observation: PerformanceObservation,
    onsetDeviation: TimeInterval,
    chordSpread: TimeInterval? = nil
) -> PerformanceAlignmentLink {
    .aligned(
        score: .init(event: event),
        observation: .init(observation: observation),
        evidence: [
            .init(dimension: .pitch, status: .observed, cost: 0),
            .init(
                dimension: .onset,
                status: .observed,
                cost: abs(onsetDeviation),
                deviationSeconds: onsetDeviation
            ),
            .init(
                dimension: .chordSpread,
                status: chordSpread == nil ? .notObserved : .observed,
                cost: chordSpread,
                deviationSeconds: chordSpread
            ),
        ]
    )
}

private func assessmentResult(
    _ dimension: PerformanceAssessmentDimension,
    in assessment: PassagePerformanceAssessment
) throws -> PerformanceAssessmentDimensionResult {
    try #require(assessment.dimensions.first { $0.dimension == dimension })
}
