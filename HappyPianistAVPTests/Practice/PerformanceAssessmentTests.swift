import Foundation
import Testing
@testable import HappyPianistAVP

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
        rubricVersion: .capabilityAware,
        dimensions: [pitch],
        measures: [.init(occurrenceID: occurrence, tickRange: 0 ..< 960, dimensions: [pitch])]
    )

    #expect(assessment.sourceGeneration == 7)
    #expect(assessment.rubricVersion == .capabilityAware)
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
func capabilityAwareRubricUsesATableForLiveAndRecordedSources() {
    let rubric = PerformanceAssessmentRubric()
    let recordedMIDI = RecordingInputSourceDescriptor(
        kind: .midi1,
        id: "recorded-midi",
        capabilities: .midi
    ).capabilities
    let rows: [(String, PerformanceInputCapabilities, Set<PerformanceAssessmentDimension>)] = [
        (
            "microphone",
            .targetAudio,
            [.duration, .release, .articulation, .velocity, .dynamicContour, .voicing, .pedalTiming, .pedalValue]
        ),
        ("midi", .midi, []),
        ("hand", .handContact, [.pedalTiming, .pedalValue]),
        ("recording", recordedMIDI, []),
    ]

    for (name, capabilities, unavailable) in rows {
        for dimension in PerformanceAssessmentDimension.allCases {
            #expect(
                (rubric.evidence(for: dimension, capabilities: capabilities) == .unavailable)
                    == unavailable.contains(dimension),
                Comment(rawValue: "\(name):\(dimension.rawValue)")
            )
        }
    }
    let degradedOnset = rubric.acceptableBands(for: .onset, capabilities: .targetAudio)
    let observedOnset = rubric.acceptableBands(for: .onset, capabilities: .midi)
    #expect(degradedOnset.first?.upperBound == 0.12)
    #expect(observedOnset.first?.upperBound == 0.08)
    #expect(observedOnset.first?.provenance == .genericApproximation)
    #expect(rubric.acceptableBands(for: .chordSpread, capabilities: .targetAudio).first?.upperBound == 0.12)
}

@Test
func targetProfilePreservesConfiguredProvenanceAndRejectsInvalidBands() throws {
    let scoreDefault = try #require(PerformanceTargetBand(
        dimension: .tempoContinuity,
        lowerBound: -0.2,
        upperBound: 0.2,
        provenance: .scoreDefault,
        sourceID: "score:rubato"
    ))
    let teacher = try #require(PerformanceTargetBand(
        dimension: .voicing,
        lowerBound: 2,
        upperBound: 5,
        provenance: .teacher,
        sourceID: "teacher:balance-a"
    ))
    let user = try #require(PerformanceTargetBand(
        dimension: .pedalTiming,
        lowerBound: -0.05,
        upperBound: 0.1,
        provenance: .userConfirmed,
        sourceID: "user:take-7"
    ))
    let profile = PerformanceTargetProfile(bands: [scoreDefault, teacher, user])

    #expect(profile.bands(for: .tempoContinuity) == [scoreDefault])
    #expect(profile.bands(for: .voicing) == [teacher])
    #expect(profile.bands(for: .pedalTiming) == [user])
    #expect(PerformanceTargetBand(
        dimension: .onset,
        lowerBound: .infinity,
        upperBound: 1,
        provenance: .teacher
    ) == nil)
    #expect(PerformanceTargetBand(
        dimension: .onset,
        lowerBound: 1,
        upperBound: -1,
        provenance: .teacher
    ) == nil)
}

@Test
func targetProfileAcceptsMultipleRubatoVoicingAndPedalInterpretations() throws {
    let bands = try [
        PerformanceTargetBand(
            dimension: .tempoContinuity,
            lowerBound: -0.4,
            upperBound: -0.2,
            provenance: .teacher,
            sourceID: "teacher:rubato-a"
        ),
        PerformanceTargetBand(
            dimension: .tempoContinuity,
            lowerBound: 0.2,
            upperBound: 0.4,
            provenance: .teacher,
            sourceID: "teacher:rubato-b"
        ),
        PerformanceTargetBand(
            dimension: .voicing,
            lowerBound: 0,
            upperBound: 2,
            provenance: .scoreDefault
        ),
        PerformanceTargetBand(
            dimension: .voicing,
            lowerBound: 5,
            upperBound: 7,
            provenance: .teacher
        ),
        PerformanceTargetBand(
            dimension: .pedalTiming,
            lowerBound: -0.2,
            upperBound: -0.1,
            provenance: .userConfirmed
        ),
        PerformanceTargetBand(
            dimension: .pedalTiming,
            lowerBound: 0.1,
            upperBound: 0.2,
            provenance: .userConfirmed
        ),
    ].map { try #require($0) }
    let rubric = PerformanceAssessmentRubric(targetProfile: PerformanceTargetProfile(bands: bands))

    #expect(rubric.accepts(-0.3, for: .tempoContinuity, capabilities: .midi))
    #expect(rubric.accepts(0.3, for: .tempoContinuity, capabilities: .midi))
    #expect(rubric.accepts(0, for: .tempoContinuity, capabilities: .midi) == false)
    #expect(rubric.accepts(1, for: .voicing, capabilities: .midi))
    #expect(rubric.accepts(6, for: .voicing, capabilities: .midi))
    #expect(rubric.accepts(3, for: .voicing, capabilities: .midi) == false)
    #expect(rubric.accepts(-0.15, for: .pedalTiming, capabilities: .midi))
    #expect(rubric.accepts(0.15, for: .pedalTiming, capabilities: .midi))
    #expect(rubric.accepts(0, for: .pedalTiming, capabilities: .midi) == false)
}

@Test
func assessmentUsesInjectedTeacherTargetInsteadOfGenericTolerance() throws {
    let event = makeAssessmentEvent()
    let plan = makeAssessmentPlan(events: [event])
    let alignment = PerformanceAlignment(
        planID: plan.id,
        sourceGeneration: 7,
        links: [makeAlignedLink(
            event: event,
            observation: makeAssessmentObservation(time: 0.15, kind: .midi1),
            onsetDeviation: 0.15
        )]
    )
    let teacherBand = try #require(PerformanceTargetBand(
        dimension: .onset,
        lowerBound: 0.14,
        upperBound: 0.16,
        provenance: .teacher,
        sourceID: "teacher:laid-back"
    ))
    let teacherService = PerformanceAssessmentService(rubric: PerformanceAssessmentRubric(
        targetProfile: PerformanceTargetProfile(bands: [teacherBand])
    ))

    let generic = try #require(PerformanceAssessmentService().assess(plan: plan, alignment: alignment, measureSpans: makeTestMeasureSpans(for: plan)))
    let teacher = try #require(teacherService.assess(plan: plan, alignment: alignment, measureSpans: makeTestMeasureSpans(for: plan)))

    #expect(try assessmentResult(.onset, in: generic).outcome == .incorrect)
    #expect(try assessmentResult(.onset, in: teacher).outcome == .correct)
}

@Test
func measureRubricUsesOnlyThatMeasuresInputCapabilities() throws {
    let events = [
        makeAssessmentEvent(ordinal: 0, onTick: 0, offTick: 480, sourceMeasureIndex: 0),
        makeAssessmentEvent(ordinal: 1, onTick: 480, offTick: 960, sourceMeasureIndex: 1),
    ]
    let plan = makeAssessmentPlan(events: events)
    let alignment = PerformanceAlignment(
        planID: plan.id,
        sourceGeneration: 7,
        links: [
            makeAlignedLink(
                event: events[0],
                observation: makeAssessmentObservation(time: 0.1, kind: .midi1),
                onsetDeviation: 0.1
            ),
            makeAlignedLink(
                event: events[1],
                observation: makeAssessmentObservation(time: 0.6, kind: .targetAudio),
                onsetDeviation: 0.1
            ),
        ]
    )

    let assessment = try #require(PerformanceAssessmentService().assess(plan: plan, alignment: alignment, measureSpans: makeTestMeasureSpans(for: plan)))
    let midiMeasure = try #require(assessment.measures.first {
        $0.occurrenceID.sourceMeasureID.sourceMeasureIndex == 0
    })
    let audioMeasure = try #require(assessment.measures.first {
        $0.occurrenceID.sourceMeasureID.sourceMeasureIndex == 1
    })

    #expect(midiMeasure.dimensions.first { $0.dimension == .onset }?.outcome == .incorrect)
    #expect(audioMeasure.dimensions.first { $0.dimension == .onset }?.outcome == .correct)
}

@Test
func mixedInputAppliesToleranceToEachSamplesEvidenceQuality() throws {
    let events = [
        makeAssessmentEvent(ordinal: 0, midiNote: 60),
        makeAssessmentEvent(ordinal: 1, midiNote: 64),
    ]
    let plan = makeAssessmentPlan(events: events)
    let alignment = PerformanceAlignment(
        planID: plan.id,
        sourceGeneration: 7,
        links: [
            makeAlignedLink(
                event: events[0],
                observation: makeAssessmentObservation(time: 0, note: 60, kind: .midi1),
                onsetDeviation: 0
            ),
            makeAlignedLink(
                event: events[1],
                observation: makeAssessmentObservation(time: 0.1, note: 64, kind: .targetAudio),
                onsetDeviation: 0.1
            ),
        ]
    )

    let assessment = try #require(PerformanceAssessmentService().assess(
        plan: plan,
        alignment: alignment,
        measureSpans: makeTestMeasureSpans(for: plan)
    ))
    let onset = try assessmentResult(.onset, in: assessment)

    #expect(onset.outcome == .correct)
    #expect(onset.evidenceStatus == .degraded)
}

@Test
func evidenceCoverageReportsCoverageWithoutProducingATotalScore() {
    let dimensions = [
        PerformanceAssessmentDimensionResult(
            dimension: .exactPitch,
            outcome: .correct,
            evidenceStatus: .observed,
            sampleCount: 1,
            evidence: []
        ),
        PerformanceAssessmentDimensionResult(
            dimension: .onset,
            outcome: .correct,
            evidenceStatus: .degraded,
            sampleCount: 1,
            evidence: []
        ),
        PerformanceAssessmentDimensionResult(
            dimension: .tempoContinuity,
            outcome: .insufficientEvidence,
            evidenceStatus: .insufficient,
            sampleCount: 0,
            evidence: []
        ),
    ]
    let coverage = PerformanceAssessmentEvidenceCoverage(dimensions: dimensions)

    #expect(coverage.dimensionCount == 3)
    #expect(coverage.observedCount == 1)
    #expect(coverage.degradedCount == 1)
    #expect(coverage.insufficientCount == 1)
    #expect(coverage.ratio == 2.0 / 3)
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

    let assessment = try #require(PerformanceAssessmentService().assess(plan: plan, alignment: alignment, measureSpans: makeTestMeasureSpans(for: plan)))
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
                evidence: [.init(dimension: .pitch, status: .observed, cost: 5)],
                noCandidateReason: .noPitchCandidate
            ),
        ]
    )

    let assessment = try #require(PerformanceAssessmentService().assess(plan: plan, alignment: alignment, measureSpans: makeTestMeasureSpans(for: plan)))
    let extra = try assessmentResult(.extraNotes, in: assessment)
    let missing = try assessmentResult(.missingNotes, in: assessment)

    #expect(extra.outcome == .incorrect)
    #expect(extra.measurement?.value == 1)
    #expect(extra.sampleCount == 1)
    #expect(missing.outcome == .incorrect)
    #expect(missing.measurement?.value == 1)
    #expect(missing.sampleCount == 1)
    #expect(assessment.measures.first?.dimensions.first { $0.dimension == .extraNotes }?.outcome == .incorrect)
}

@Test
func unlocalizedExtraNoteRemainsAPassageFactInsteadOfInventingMeasureEvidence() throws {
    let events = [
        makeAssessmentEvent(ordinal: 0, onTick: 0, offTick: 480, sourceMeasureIndex: 0),
        makeAssessmentEvent(ordinal: 1, onTick: 480, offTick: 960, sourceMeasureIndex: 1),
    ]
    let plan = makeAssessmentPlan(events: events)
    let extra = makeAssessmentObservation(id: UUID(), time: 0.3, note: 67)
    let alignment = PerformanceAlignment(
        planID: plan.id,
        sourceGeneration: 7,
        links: [
            makeAlignedLink(
                event: events[0],
                observation: makeAssessmentObservation(time: 0, note: 60),
                onsetDeviation: 0
            ),
            makeAlignedLink(
                event: events[1],
                observation: makeAssessmentObservation(time: 0.5, note: 60),
                onsetDeviation: 0
            ),
            .extra(
                observation: .init(observation: extra),
                evidence: [.init(dimension: .pitch, status: .observed, cost: 5)],
                noCandidateReason: nil
            ),
        ]
    )

    let assessment = try #require(PerformanceAssessmentService().assess(plan: plan, alignment: alignment, measureSpans: makeTestMeasureSpans(for: plan)))
    #expect(try assessmentResult(.extraNotes, in: assessment).outcome == .incorrect)
    #expect(assessment.measures.count == 2)
    for measure in assessment.measures {
        #expect(measure.dimensions.contains { $0.dimension == .extraNotes } == false)
    }
}

@Test
func multipartLogicalPianoUsesTheAuthoritativeStructuralMeasure() throws {
    let right = makeAssessmentEvent(ordinal: 0, midiNote: 64, partID: "P1")
    let left = makeAssessmentEvent(ordinal: 1, midiNote: 48, staff: 2, partID: "P2")
    let plan = makeAssessmentPlan(events: [right, left])
    let links = [right, left].map { event in
        makeAlignedLink(
            event: event,
            observation: makeAssessmentObservation(time: 0, note: event.midiNote),
            onsetDeviation: 0
        )
    }
    let structuralSpan = MusicXMLMeasureSpan(
        partID: "P1",
        measureNumber: 1,
        sourceMeasureIndex: 0,
        sourceMeasureNumberToken: "1",
        occurrenceIndex: 0,
        startTick: 0,
        endTick: 480
    )

    let assessment = try #require(PerformanceAssessmentService().assess(
        plan: plan,
        alignment: .init(planID: plan.id, sourceGeneration: 7, links: links),
        measureSpans: [structuralSpan]
    ))

    #expect(assessment.measures.count == 1)
    let measure = try #require(assessment.measures.first)
    #expect(measure.occurrenceID == structuralSpan.occurrenceID)
    #expect(measure.dimensions.first { $0.dimension == .exactPitch }?.sampleCount == 2)
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

        let assessment = try #require(PerformanceAssessmentService().assess(plan: plan, alignment: alignment, measureSpans: makeTestMeasureSpans(for: plan)))
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

    let assessment = try #require(PerformanceAssessmentService().assess(plan: plan, alignment: alignment, measureSpans: makeTestMeasureSpans(for: plan)))
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

    let assessment = try #require(PerformanceAssessmentService().assess(plan: plan, alignment: alignment, measureSpans: makeTestMeasureSpans(for: plan)))
    let onset = try assessmentResult(.onset, in: assessment)

    #expect(onset.sampleCount == 3)
    #expect(onset.outcome == .correct)
    #expect(assessment.dimensions.contains { $0.dimension == .chordSpread } == false)
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

    let assessment = try #require(PerformanceAssessmentService().assess(plan: plan, alignment: alignment, measureSpans: makeTestMeasureSpans(for: plan)))
    let pitch = try assessmentResult(.exactPitch, in: assessment)
    let onset = try assessmentResult(.onset, in: assessment)

    #expect(pitch.outcome == .insufficientEvidence)
    #expect(pitch.evidenceStatus == .insufficient)
    #expect(pitch.sampleCount == 0)
    #expect(onset.outcome == .insufficientEvidence)
    #expect(onset.outcome != .incorrect)
}

@Test
func mixedResolvedAndAmbiguousEvidenceCannotBecomeCorrect() throws {
    let events = [
        makeAssessmentEvent(ordinal: 0, midiNote: 60),
        makeAssessmentEvent(ordinal: 1, midiNote: 64, onTick: 480, offTick: 960),
    ]
    let plan = makeAssessmentPlan(events: events)
    let alignedObservation = makeAssessmentObservation(time: 0, note: 60)
    let ambiguousObservation = makeAssessmentObservation(time: 0.5, note: 64)
    let candidate = PerformanceAlignmentCandidate(
        score: .init(event: events[1]),
        totalCost: 0,
        evidence: [
            .init(dimension: .pitch, status: .observed, cost: 0),
            .init(dimension: .onset, status: .observed, cost: 0, deviationSeconds: 0),
        ]
    )
    let alignment = PerformanceAlignment(
        planID: plan.id,
        sourceGeneration: 7,
        links: [
            makeAlignedLink(event: events[0], observation: alignedObservation, onsetDeviation: 0),
            .ambiguous(observation: .init(observation: ambiguousObservation), candidates: [candidate]),
        ]
    )

    let assessment = try #require(PerformanceAssessmentService().assess(plan: plan, alignment: alignment, measureSpans: makeTestMeasureSpans(for: plan)))
    for dimension in [PerformanceAssessmentDimension.exactPitch, .extraNotes, .missingNotes, .onset] {
        let result = try assessmentResult(dimension, in: assessment)
        #expect(result.outcome == .insufficientEvidence)
        #expect(result.evidenceStatus == .insufficient)
        #expect(result.evidence.contains { evidence in
            if case let .ambiguousObservation(id) = evidence { id == ambiguousObservation.id } else { false }
        })
    }
    let measure = try #require(assessment.measures.first)
    #expect(measure.dimensions.first { $0.dimension == .exactPitch }?.outcome == .insufficientEvidence)
}

@Test
func durationUsesPerformedTargetAndKeepsStaccatoRatioSeparateFromWrittenDuration() throws {
    let event = makeAssessmentEvent(offTick: 480, performedOffTick: 240)
    let plan = makeAssessmentPlan(events: [event])
    let observation = makeAssessmentObservation(time: 0)
    let alignment = PerformanceAlignment(
        planID: plan.id,
        sourceGeneration: 7,
        links: [makeAlignedLink(
            event: event,
            observation: observation,
            onsetDeviation: 0,
            releaseDeviation: 0,
            releaseStatus: .observed
        )]
    )

    let assessment = try #require(PerformanceAssessmentService().assess(plan: plan, alignment: alignment, measureSpans: makeTestMeasureSpans(for: plan)))
    let duration = try assessmentResult(.duration, in: assessment)
    let release = try assessmentResult(.release, in: assessment)

    #expect(duration.outcome == .correct)
    #expect(duration.measurement?.unit == .ratio)
    #expect(duration.measurement?.value == 1)
    #expect(release.outcome == .correct)
    #expect(release.measurement?.value == 0)
}

@Test
func durationAndReleaseExposePrematureReleaseWithoutCollapsingTheirUnits() throws {
    let event = makeAssessmentEvent()
    let plan = makeAssessmentPlan(events: [event])
    let alignment = PerformanceAlignment(
        planID: plan.id,
        sourceGeneration: 7,
        links: [makeAlignedLink(
            event: event,
            observation: makeAssessmentObservation(time: 0),
            onsetDeviation: 0,
            releaseDeviation: -0.2,
            releaseStatus: .observed
        )]
    )

    let assessment = try #require(PerformanceAssessmentService().assess(plan: plan, alignment: alignment, measureSpans: makeTestMeasureSpans(for: plan)))
    let duration = try assessmentResult(.duration, in: assessment)
    let release = try assessmentResult(.release, in: assessment)

    #expect(duration.outcome == .incorrect)
    #expect(abs((duration.measurement?.value ?? 0) - 0.6) < 0.000_001)
    #expect(release.outcome == .incorrect)
    #expect(abs((release.measurement?.value ?? 0) + 0.2) < 0.000_001)
}

@Test
func releaseIncludesOnsetDeviationWhileDurationDoesNot() throws {
    let event = makeAssessmentEvent()
    let plan = makeAssessmentPlan(events: [event])
    let alignment = PerformanceAlignment(
        planID: plan.id,
        sourceGeneration: 7,
        links: [makeAlignedLink(
            event: event,
            observation: makeAssessmentObservation(time: 0.12),
            onsetDeviation: 0.12,
            releaseDeviation: 0,
            releaseStatus: .observed
        )]
    )

    let assessment = try #require(PerformanceAssessmentService().assess(plan: plan, alignment: alignment, measureSpans: makeTestMeasureSpans(for: plan)))
    let duration = try assessmentResult(.duration, in: assessment)
    let release = try assessmentResult(.release, in: assessment)

    #expect(duration.outcome == .correct)
    #expect(duration.measurement?.value == 1)
    #expect(release.outcome == .incorrect)
    #expect(abs((release.measurement?.value ?? 0) - 0.12) < 0.000_001)
}

@Test
func articulationPreservesLegatoOverlapAndGapDirection() throws {
    let events = [
        makeAssessmentEvent(ordinal: 0, midiNote: 60, onTick: 0, offTick: 480),
        makeAssessmentEvent(ordinal: 1, midiNote: 62, onTick: 480, offTick: 960),
    ]
    let plan = makeAssessmentPlan(events: events)

    for (nextOnset, expectedGap, expectedOutcome) in [
        (0.48, -0.02, PracticeEvidenceOutcome.correct),
        (0.62, 0.12, PracticeEvidenceOutcome.incorrect),
    ] {
        let alignment = PerformanceAlignment(
            planID: plan.id,
            sourceGeneration: 7,
            links: [
                makeAlignedLink(
                    event: events[0],
                    observation: makeAssessmentObservation(time: 0, note: 60),
                    onsetDeviation: 0,
                    releaseDeviation: 0,
                    releaseStatus: .observed
                ),
                makeAlignedLink(
                    event: events[1],
                    observation: makeAssessmentObservation(time: nextOnset, note: 62),
                    onsetDeviation: nextOnset - 0.5,
                    releaseDeviation: 0,
                    releaseStatus: .observed
                ),
            ]
        )

        let assessment = try #require(PerformanceAssessmentService().assess(plan: plan, alignment: alignment, measureSpans: makeTestMeasureSpans(for: plan)))
        let articulation = try assessmentResult(.articulation, in: assessment)

        #expect(articulation.outcome == expectedOutcome)
        #expect(abs((articulation.measurement?.value ?? 0) - expectedGap) < 0.000_001)
        #expect(articulation.sampleCount == 1)
    }
}

@Test
func unavailableNoteOffCapabilityLeavesDurationReleaseAndArticulationNotObserved() throws {
    let event = makeAssessmentEvent()
    let plan = makeAssessmentPlan(events: [event])
    let alignment = PerformanceAlignment(
        planID: plan.id,
        sourceGeneration: 7,
        links: [makeAlignedLink(
            event: event,
            observation: makeAssessmentObservation(time: 0),
            onsetDeviation: 0
        )]
    )

    let assessment = try #require(PerformanceAssessmentService().assess(plan: plan, alignment: alignment, measureSpans: makeTestMeasureSpans(for: plan)))
    for dimension in [
        PerformanceAssessmentDimension.duration,
        .release,
        .articulation,
    ] {
        #expect(assessment.dimensions.contains { $0.dimension == dimension } == false)
    }
}

@Test
func availableReleaseCapabilityWithoutNoteOffIsInsufficientRatherThanWrong() throws {
    let event = makeAssessmentEvent()
    let plan = makeAssessmentPlan(events: [event])
    let alignment = PerformanceAlignment(
        planID: plan.id,
        sourceGeneration: 7,
        links: [makeAlignedLink(
            event: event,
            observation: makeAssessmentObservation(time: 0),
            onsetDeviation: 0,
            releaseStatus: .observed
        )]
    )

    let assessment = try #require(PerformanceAssessmentService().assess(plan: plan, alignment: alignment, measureSpans: makeTestMeasureSpans(for: plan)))
    #expect(try assessmentResult(.duration, in: assessment).outcome == .insufficientEvidence)
    #expect(try assessmentResult(.release, in: assessment).outcome == .insufficientEvidence)
}

@Test
func velocityAndDynamicContourFollowPlanTargetsIncludingAccentDelta() throws {
    let events = [
        makeAssessmentEvent(ordinal: 0, midiNote: 60, onTick: 0, offTick: 480, velocity: 60),
        makeAssessmentEvent(
            ordinal: 1,
            midiNote: 62,
            onTick: 480,
            offTick: 960,
            velocity: 90,
            articulationDelta: 10
        ),
    ]
    let plan = makeAssessmentPlan(events: events)

    for (performedSecond, expectedOutcome) in [
        (90, PracticeEvidenceOutcome.correct),
        (65, PracticeEvidenceOutcome.incorrect),
    ] {
        let alignment = PerformanceAlignment(
            planID: plan.id,
            sourceGeneration: 7,
            links: [
                makeAlignedLink(
                    event: events[0],
                    observation: makeAssessmentObservation(time: 0, note: 60, velocity: 60),
                    onsetDeviation: 0
                ),
                makeAlignedLink(
                    event: events[1],
                    observation: makeAssessmentObservation(time: 0.5, note: 62, velocity: performedSecond),
                    onsetDeviation: 0
                ),
            ]
        )

        let assessment = try #require(PerformanceAssessmentService().assess(plan: plan, alignment: alignment, measureSpans: makeTestMeasureSpans(for: plan)))
        let contour = try assessmentResult(.dynamicContour, in: assessment)

        #expect(contour.outcome == expectedOutcome)
        #expect(contour.sampleCount == 1)
        if expectedOutcome == .correct {
            #expect(try assessmentResult(.velocity, in: assessment).outcome == .correct)
            #expect(abs(contour.measurement?.value ?? 1) < 0.000_001)
        } else {
            #expect(abs((contour.measurement?.value ?? 0) + 25) < 0.000_001)
        }
    }
}

@Test
func genericDynamicBaselineDegradesVelocityConclusion() throws {
    func velocityStatus(usesGenericBaseline: Bool) throws -> PerformanceAssessmentEvidenceStatus {
        let event = makeAssessmentEvent(
            velocity: 90,
            usesGenericDynamicBaseline: usesGenericBaseline
        )
        let plan = makeAssessmentPlan(events: [event])
        let alignment = PerformanceAlignment(
            planID: plan.id,
            sourceGeneration: 7,
            links: [makeAlignedLink(
                event: event,
                observation: makeAssessmentObservation(time: 0, velocity: 90),
                onsetDeviation: 0
            )]
        )
        let assessment = try #require(PerformanceAssessmentService().assess(
            plan: plan,
            alignment: alignment,
            measureSpans: makeTestMeasureSpans(for: plan)
        ))
        return try assessmentResult(.velocity, in: assessment).evidenceStatus
    }

    #expect(try velocityStatus(usesGenericBaseline: true) == .degraded)
    #expect(try velocityStatus(usesGenericBaseline: false) == .observed)
}

@Test
func genericVoicingUsesTraceableVoiceHandAndFingeringInsteadOfHighestPitch() throws {
    let rightHand = ScoreHandAssignment(hand: .right, provenance: .score)
    let events = [
        makeAssessmentEvent(
            ordinal: 0,
            midiNote: 60,
            velocity: 100,
            voice: 1,
            handAssignment: rightHand,
            fingerings: [.init(text: "1", hand: .right, provenance: .score)]
        ),
        makeAssessmentEvent(
            ordinal: 1,
            midiNote: 72,
            velocity: 70,
            voice: 2,
            handAssignment: rightHand,
            fingerings: [.init(text: "5", hand: .right, provenance: .teacher)]
        ),
    ]
    let plan = makeAssessmentPlan(events: events)
    let alignment = PerformanceAlignment(
        planID: plan.id,
        sourceGeneration: 7,
        links: events.map { event in
            makeAlignedLink(
                event: event,
                observation: makeAssessmentObservation(
                    time: 0,
                    note: event.midiNote,
                    velocity: Int(event.velocity)
                ),
                onsetDeviation: 0,
                chordSpread: 0
            )
        }
    )

    let assessment = try #require(PerformanceAssessmentService().assess(plan: plan, alignment: alignment, measureSpans: makeTestMeasureSpans(for: plan)))
    let voicing = try assessmentResult(.voicing, in: assessment)

    #expect(voicing.outcome == .correct)
    #expect(voicing.evidenceStatus == .degraded)
    #expect(voicing.sampleCount == 1)
    #expect(abs(voicing.measurement?.value ?? 1) < 0.000_001)
}

@Test
func calibratedHandVelocitySurvivesCommittedAlignmentWithDegradedConfidence() throws {
    let event = makeAssessmentEvent(velocity: 90)
    let plan = makeAssessmentPlan(events: [event])
    let observation = makeAssessmentObservation(
        time: 0,
        note: 60,
        velocity: 90,
        kind: .realPianoContact,
        calibrationReference: "calibration-1"
    )
    let alignment = PerformanceAlignment(
        planID: plan.id,
        sourceGeneration: 7,
        links: [makeAlignedLink(event: event, observation: observation, onsetDeviation: 0)]
    )

    let assessment = try #require(PerformanceAssessmentService().assess(plan: plan, alignment: alignment, measureSpans: makeTestMeasureSpans(for: plan)))
    let velocity = try assessmentResult(.velocity, in: assessment)
    let reference = PerformanceAlignmentObservationReference(observation: observation)

    #expect(velocity.outcome == .correct)
    #expect(velocity.evidenceStatus == .degraded)
    #expect(velocity.confidence == 0.5)
    #expect(reference.onsetVelocity != nil)
    #expect(reference.calibrationReference == "calibration-1")
}

@Test
func recordedTakeRebasingPreservesCalibratedHandVelocity() throws {
    let event = makeAssessmentEvent()
    let plan = makeAssessmentPlan(events: [event])
    let observation = makeAssessmentObservation(
        time: 40,
        note: 60,
        velocity: 88,
        kind: .realPianoContact,
        calibrationReference: "calibration-1"
    )
    let take = RecordingTake(
        name: "hand-velocity",
        metadata: .init(scoreIdentity: plan.sourceScoreIdentity, inputSources: []),
        events: [.init(time: 0, kind: .noteOn(midi: 60, velocity: 88), observation: observation)]
    )

    let rebased = try #require(take.alignmentObservations()?.first)

    #expect(rebased.alignmentTimestamp.seconds == 0)
    #expect(rebased.onsetVelocity == observation.onsetVelocity)
    #expect(rebased.calibrationReference == observation.calibrationReference)
}

@Test
func unavailableVelocityCapabilityDoesNotScoreDynamicsAsZero() throws {
    let event = makeAssessmentEvent()
    let plan = makeAssessmentPlan(events: [event])
    let observation = makeAssessmentObservation(
        time: 0,
        note: 60,
        velocity: nil,
        kind: .targetAudio
    )
    let alignment = PerformanceAlignment(
        planID: plan.id,
        sourceGeneration: 7,
        links: [makeAlignedLink(event: event, observation: observation, onsetDeviation: 0)]
    )

    let assessment = try #require(PerformanceAssessmentService().assess(plan: plan, alignment: alignment, measureSpans: makeTestMeasureSpans(for: plan)))
    #expect(assessment.dimensions.contains { $0.dimension == .velocity } == false)
    #expect(assessment.dimensions.contains { $0.dimension == .dynamicContour } == false)
    #expect(assessment.dimensions.contains { $0.dimension == .voicing } == false)
}

@Test
func pedalAssessmentMeasuresChangeValueAndSignedOverlapGap() throws {
    let events = [makeAssessmentEvent()]
    let controllers = [
        makeAssessmentController(tick: 0, value: 127),
        makeAssessmentController(tick: 480, value: 0),
    ]
    let plan = makeAssessmentPlan(events: events, controllerEvents: controllers)
    let observations = [
        makeAssessmentControllerObservation(time: 0, value: 127),
        makeAssessmentControllerObservation(time: 0.75, value: 25),
    ]
    let alignment = PerformanceAlignment(
        planID: plan.id,
        sourceGeneration: 7,
        links: [],
        controllerLinks: [
            .aligned(
                score: .init(event: controllers[0]),
                observation: .init(observation: observations[0]),
                timeDeviationSeconds: 0,
                normalizedValueDeviation: 0
            ),
            .aligned(
                score: .init(event: controllers[1]),
                observation: .init(observation: observations[1]),
                timeDeviationSeconds: 0.25,
                normalizedValueDeviation: 25.0 / 127
            ),
        ]
    )

    let assessment = try #require(PerformanceAssessmentService().assess(plan: plan, alignment: alignment, measureSpans: makeTestMeasureSpans(for: plan)))
    let timing = try assessmentResult(.pedalTiming, in: assessment)
    let value = try assessmentResult(.pedalValue, in: assessment)

    #expect(timing.outcome == .incorrect)
    #expect(timing.evidenceStatus == .degraded)
    #expect(timing.sampleCount == 3)
    #expect(timing.measurement?.value == 0.25)
    #expect(value.outcome == .incorrect)
    #expect(value.evidenceStatus == .degraded)
    #expect(value.sampleCount == 2)
    #expect(value.measurement?.unit == .normalized)
    #expect(timing.evidence.allSatisfy { evidence in
        if case .controller = evidence { true } else { false }
    })
}

@Test
func unavailableControllerCapabilityLeavesPedalDimensionsNotObserved() throws {
    let event = makeAssessmentEvent()
    let controller = makeAssessmentController(tick: 0, value: 127)
    let plan = makeAssessmentPlan(events: [event], controllerEvents: [controller])
    let alignment = PerformanceAlignment(
        planID: plan.id,
        sourceGeneration: 7,
        links: [],
        controllerLinks: [.notObserved(score: .init(event: controller))]
    )

    let assessment = try #require(PerformanceAssessmentService().assess(plan: plan, alignment: alignment, measureSpans: makeTestMeasureSpans(for: plan)))
    for dimension in [PerformanceAssessmentDimension.pedalTiming, .pedalValue] {
        #expect(assessment.dimensions.contains { $0.dimension == dimension } == false)
    }
}

@Test
func tempoAndPhraseContinuityAllowLinearRubatoAndMarkGenericBaselinesDegraded() throws {
    let events = (0 ..< 4).map { index in
        makeAssessmentEvent(
            ordinal: index,
            midiNote: 60 + index,
            onTick: index * 480,
            offTick: (index + 1) * 480
        )
    }
    let plan = makeAssessmentPlan(events: events)
    let links = zip(events, [0.0, 0.1, 0.2, 0.3]).map { event, deviation in
        makeAlignedLink(
            event: event,
            observation: makeAssessmentObservation(time: deviation, note: event.midiNote),
            onsetDeviation: deviation
        )
    }
    let alignment = PerformanceAlignment(planID: plan.id, sourceGeneration: 7, links: links)

    let assessment = try #require(PerformanceAssessmentService().assess(plan: plan, alignment: alignment, measureSpans: makeTestMeasureSpans(for: plan)))
    let tempo = try assessmentResult(.tempoContinuity, in: assessment)
    let phrase = try assessmentResult(.phraseContinuity, in: assessment)

    #expect(tempo.outcome == .correct)
    #expect(tempo.evidenceStatus == .degraded)
    #expect(abs(tempo.measurement?.value ?? 1) < 0.000_001)
    #expect(phrase.outcome == .correct)
    #expect(phrase.evidenceStatus == .degraded)
    #expect(abs(phrase.measurement?.value ?? 1) < 0.000_001)
}

@Test
func explicitTempoSourceKeepsContinuityEvidenceObserved() throws {
    let events = (0 ..< 4).map { index in
        makeAssessmentEvent(
            ordinal: index,
            midiNote: 60 + index,
            onTick: index * 480,
            offTick: (index + 1) * 480
        )
    }
    let sourceID = MusicXMLDirectionSourceID(
        partID: "P1",
        sourceMeasureIndex: 0,
        sourceMeasureNumberToken: "1",
        sourceOrdinal: 0
    )
    let plan = makeAssessmentPlan(events: events, tempoEvents: [.init(
        sourceDirectionID: sourceID,
        performedOccurrenceIndex: 0,
        tick: 0,
        quarterBPM: 120,
        endTick: nil,
        endQuarterBPM: nil
    )])
    let links = events.map { event in
        makeAlignedLink(
            event: event,
            observation: makeAssessmentObservation(time: 0, note: event.midiNote),
            onsetDeviation: 0
        )
    }
    let assessment = try #require(PerformanceAssessmentService().assess(
        plan: plan,
        alignment: .init(planID: plan.id, sourceGeneration: 7, links: links),
        measureSpans: makeTestMeasureSpans(for: plan)
    ))

    #expect(try assessmentResult(.tempoContinuity, in: assessment).evidenceStatus == .observed)
}

@Test
func tempoWordBoundaryDoesNotTurnRubatoIntoAContinuityError() throws {
    let events = (0 ..< 6).map { index in
        makeAssessmentEvent(
            ordinal: index,
            midiNote: 60 + index,
            onTick: index * 240,
            offTick: (index + 1) * 240
        )
    }
    let annotation = ScorePerformanceAnnotation(
        sourceDirectionID: nil,
        performedOccurrenceIndex: 0,
        tick: 720,
        durationTicks: nil,
        kind: .tempoWord,
        text: "rubato",
        provenance: [.init(kind: .score, sourceIdentity: nil, detail: nil)]
    )
    let plan = makeAssessmentPlan(events: events, annotations: [annotation])
    let deviations = [0.0, 0, 0, 0.4, 0.6, 0.8]
    let links = zip(events, deviations).map { event, deviation in
        makeAlignedLink(
            event: event,
            observation: makeAssessmentObservation(time: deviation, note: event.midiNote),
            onsetDeviation: deviation
        )
    }
    let alignment = PerformanceAlignment(planID: plan.id, sourceGeneration: 7, links: links)

    let assessment = try #require(PerformanceAssessmentService().assess(plan: plan, alignment: alignment, measureSpans: makeTestMeasureSpans(for: plan)))

    #expect(try assessmentResult(.tempoContinuity, in: assessment).outcome == .correct)
    #expect(try assessmentResult(.phraseContinuity, in: assessment).outcome == .correct)
}

@Test
func alignmentIgnoresNonPedalControlChangesForPedalAssessment() {
    let event = makeAssessmentEvent()
    let plan = makeAssessmentPlan(events: [event])
    let modulation = makeAssessmentControllerObservation(time: 0, number: 1, value: 127)

    let alignment = PerformanceAlignmentEngine().align(
        plan: plan,
        observations: [modulation],
        performanceStart: .init(seconds: 0),
        generation: 7
    )

    #expect(alignment.controllerLinks.isEmpty)
}

@Test
func analyzerPublishesAssessmentFromCommittedAndFinishedAlignment() async throws {
    let event = makeAssessmentEvent()
    let plan = makeAssessmentPlan(events: [event])
    let analyzer = PracticePerformanceAnalyzer()
    let start = PerformanceMonotonicInstant(seconds: 5)

    await analyzer.configure(plan: plan, measureSpans: makeTestMeasureSpans(for: plan), activeTickRange: nil)
    await analyzer.beginRound(at: start)
    await analyzer.record(makeAssessmentObservation(time: 5))
    let runningSnapshot = await analyzer.snapshot()
    let snapshot = await analyzer.finishRound()

    #expect(runningSnapshot.assessment != nil)
    #expect(runningSnapshot.isRunning)
    let assessment = try #require(snapshot.assessment)
    #expect(snapshot.alignment != nil)
    #expect(try assessmentResult(.exactPitch, in: assessment).outcome == .correct)
    #expect(try assessmentResult(.velocity, in: assessment).outcome == .correct)
}

@Test
func analyzerPublishesMissingAssessmentForSilentRoundAndFinishesIdempotently() async throws {
    let event = makeAssessmentEvent()
    let plan = makeAssessmentPlan(events: [event])
    let analyzer = PracticePerformanceAnalyzer()

    await analyzer.configure(plan: plan, measureSpans: makeTestMeasureSpans(for: plan), activeTickRange: nil)
    await analyzer.beginRound(at: .init(seconds: 5))
    await analyzer.registerInputCapabilities(.midi)
    let first = await analyzer.finishRound()
    let second = await analyzer.finishRound()

    let alignment = try #require(first.alignment)
    let assessment = try #require(first.assessment)
    #expect(alignment.links.contains { link in
        guard case let .missing(score, _) = link else { return false }
        return score.eventID == event.id
    })
    #expect(assessment.planID == plan.id)
    #expect(try assessmentResult(.missingNotes, in: assessment).outcome == .incorrect)
    #expect(assessment.measures.first?.dimensions.first { $0.dimension == .missingNotes }?.outcome == .incorrect)
    #expect(first == second)
    #expect(first.isRunning == false)
}

@Test
func analyzerDoesNotInventMissingFactsWhenNoInputActuallyStarted() async throws {
    let event = makeAssessmentEvent()
    let plan = makeAssessmentPlan(events: [event])
    let analyzer = PracticePerformanceAnalyzer()

    await analyzer.configure(plan: plan, measureSpans: makeTestMeasureSpans(for: plan), activeTickRange: nil)
    await analyzer.beginRound(at: .init(seconds: 5))
    let snapshot = await analyzer.finishRound()

    #expect(try #require(snapshot.assessment).dimensions.isEmpty)
}

private func makeAssessmentEvent(
    ordinal: Int = 0,
    midiNote: Int = 60,
    onTick: Int = 0,
    offTick: Int = 480,
    writtenOffTick: Int? = nil,
    performedOffTick: Int? = nil,
    velocity: UInt8 = 90,
    usesGenericDynamicBaseline: Bool = false,
    articulationDelta: Int = 0,
    staff: Int = 1,
    voice: Int = 1,
    handAssignment: ScoreHandAssignment = .unknown,
    fingerings: [MusicXMLFingering] = [],
    timingProvenance: [ScorePerformanceProvenance] = [],
    sourceMeasureIndex: Int = 0,
    partID: String = "P1"
) -> ScorePerformanceNoteEvent {
    let sourceID = MusicXMLSourceNoteID(
        partID: partID,
        sourceMeasureIndex: sourceMeasureIndex,
        sourceMeasureNumberToken: String(sourceMeasureIndex + 1),
        staff: staff,
        voice: voice,
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
        writtenOffTick: writtenOffTick ?? offTick,
        performedOnTick: onTick,
        performedOffTick: performedOffTick ?? offTick,
        writtenPitch: nil,
        midiNote: midiNote,
        velocityResolution: .init(
            baseVelocity: Int(velocity) - articulationDelta,
            curveVelocity: nil,
            articulationDelta: articulationDelta,
            unclampedVelocity: Int(velocity),
            velocity: velocity,
            usesGenericDynamicBaseline: usesGenericDynamicBaseline
        ),
        staff: staff,
        voice: voice,
        handAssignment: handAssignment,
        fingerings: fingerings,
        timingProvenance: timingProvenance
    )
}

private func makeAssessmentPlan(
    events: [ScorePerformanceNoteEvent],
    tempoEvents: [ScorePerformanceTempoEvent]? = nil,
    controllerEvents: [ScorePerformanceControllerEvent] = [],
    annotations: [ScorePerformanceAnnotation] = [],
    approximations: [ScorePerformanceApproximation] = []
) -> ScorePerformancePlan {
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
        tempoEvents: tempoEvents ?? [.init(
            sourceDirectionID: nil,
            performedOccurrenceIndex: 0,
            tick: 0,
            quarterBPM: 120,
            endTick: nil,
            endQuarterBPM: nil
        )],
        controllerEvents: controllerEvents,
        annotations: annotations,
        approximations: approximations
    )
}

private func makeAssessmentController(
    tick: Int,
    value: UInt8,
    number: UInt8 = MusicXMLPedalController.damper.rawValue
) -> ScorePerformanceControllerEvent {
    ScorePerformanceControllerEvent(
        sourceDirectionID: nil,
        performedOccurrenceIndex: 0,
        tick: tick,
        controllerNumber: number,
        value: value,
        outputCapabilityRequirement: .continuousControlChange
    )
}

private func makeAssessmentControllerObservation(
    time: TimeInterval,
    number: Int = Int(MusicXMLPedalController.damper.rawValue),
    value: Int
) -> PerformanceObservation {
    let instant = PerformanceMonotonicInstant(seconds: time)
    return PerformanceObservation(
        source: .init(kind: .midi1, id: "assessment-midi", generation: 7),
        timing: .init(
            host: instant,
            source: nil,
            correctedHost: instant,
            mapping: nil,
            provenance: .hostOnly
        ),
        event: .controller(.controlChange(number: number, value: .init(midi1: value)))
    )
}

private func makeAssessmentObservation(
    id: UUID = UUID(),
    time: TimeInterval,
    note: Int = 60,
    velocity: Int? = 90,
    kind: PerformanceObservation.Source.Kind = .midi1,
    calibrationReference: String? = nil
) -> PerformanceObservation {
    let instant = PerformanceMonotonicInstant(seconds: time)
    let event: PerformanceObservation.Event = switch kind {
    case .midi1, .midi2:
        .noteOn(note: note, velocity: velocity.map { .init(midi1: $0) })
    case .targetAudio:
        .targetAudioDetection(
            targetMIDINotes: [note],
            detectedMIDINotes: [note],
            result: .detected
        )
    case .realPianoContact, .virtualPianoContact:
        .contact(id: "contact", keyCandidate: note, phase: .started)
    }
    return PerformanceObservation(
        id: id,
        source: .init(kind: kind, id: "assessment-input", generation: 7),
        timing: .init(
            host: instant,
            source: nil,
            correctedHost: instant,
            mapping: nil,
            provenance: .hostOnly
        ),
        event: event,
        onsetVelocity: kind == .realPianoContact || kind == .virtualPianoContact
            ? velocity.map { .init(midi1: $0) }
            : nil,
        calibrationReference: calibrationReference
    )
}

private func makeAlignedLink(
    event: ScorePerformanceNoteEvent,
    observation: PerformanceObservation,
    onsetDeviation: TimeInterval,
    chordSpread: TimeInterval? = nil,
    releaseDeviation: TimeInterval? = nil,
    releaseStatus: PerformanceAlignmentEvidenceStatus = .notObserved
) -> PerformanceAlignmentLink {
    let pitchStatus: PerformanceAlignmentEvidenceStatus = switch observation.source.capabilities.pitch {
    case .observed: .observed
    case .degraded: .degraded
    case .unavailable: .notObserved
    }
    let onsetStatus: PerformanceAlignmentEvidenceStatus = switch observation.source.capabilities.onset {
    case .observed: .observed
    case .degraded: .degraded
    case .unavailable: .notObserved
    }
    let velocityStatus: PerformanceAlignmentEvidenceStatus = switch observation.source.capabilities.velocity {
    case .observed: .observed
    case .degraded: .degraded
    case .unavailable: .notObserved
    }
    return .aligned(
        score: .init(event: event),
        observation: .init(observation: observation),
        evidence: [
            .init(dimension: .pitch, status: pitchStatus, cost: 0),
            .init(
                dimension: .onset,
                status: onsetStatus,
                cost: abs(onsetDeviation),
                deviationSeconds: onsetDeviation
            ),
            .init(
                dimension: .chordSpread,
                status: chordSpread == nil ? .notObserved : onsetStatus,
                cost: chordSpread,
                deviationSeconds: chordSpread
            ),
            .init(
                dimension: .release,
                status: releaseStatus,
                cost: releaseDeviation.map { abs(onsetDeviation + $0) },
                deviationSeconds: releaseDeviation.map { onsetDeviation + $0 }
            ),
            .init(
                dimension: .duration,
                status: releaseStatus,
                cost: releaseDeviation.map(abs),
                deviationSeconds: releaseDeviation
            ),
            .init(
                dimension: .velocity,
                status: velocityStatus
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
