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
func duplicateStableIDsAreIgnoredAtAlignmentBoundaries() throws {
    let event = makeAlignmentEvent(
        sourceID: makeAlignmentSourceID(ordinal: 0),
        occurrenceIndex: 0
    )
    let plan = makeAlignmentPlan(noteEvents: [event, event])
    let observationID = UUID()
    let first = makeAlignmentObservation(id: observationID, generation: 1, seconds: 0)
    let duplicate = makeAlignmentObservation(id: observationID, generation: 1, seconds: 0.1)

    let offline = PerformanceAlignmentEngine().align(
        plan: plan,
        observations: [first, duplicate],
        performanceStart: .init(seconds: 0),
        generation: 1
    )
    #expect(offline.links.filter { if case .aligned = $0 { true } else { false } }.count == 1)
    #expect(offline.links.filter { if case .missing = $0 { true } else { false } }.isEmpty)
    #expect(offline.links.filter { if case .extra = $0 { true } else { false } }.isEmpty)

    var online = IncrementalPerformanceAligner()
    online.start(plan: plan, generation: 1, performanceStart: .init(seconds: 0))
    #expect(online.append(first) != nil)
    #expect(online.append(duplicate) == nil)
    #expect(online.finish() == offline)
}

@Test
func alignmentEngineUsesCapabilitiesRangeGenerationAndPlanResolution() throws {
    let sourceID = makeAlignmentSourceID(ordinal: 0)
    let event = makeAlignmentEvent(
        sourceID: sourceID,
        occurrenceIndex: 0,
        onTick: 960
    )
    let plan = makeAlignmentPlan(noteEvents: [event], ticksPerQuarter: 960)
    let engine = PerformanceAlignmentEngine()
    let exact = engine.align(
        plan: plan,
        observations: [makeAlignmentObservation(generation: 9, note: 60, seconds: 0.5)],
        performanceStart: .init(seconds: 0),
        activeTickRange: 0 ..< 1_920,
        generation: 9,
        includeMissing: false
    )
    let wrong = engine.align(
        plan: plan,
        observations: [makeAlignmentObservation(generation: 9, note: 61, seconds: 0.5)],
        performanceStart: .init(seconds: 0),
        activeTickRange: 0 ..< 1_920,
        generation: 9,
        includeMissing: false
    )
    let stale = engine.align(
        plan: plan,
        observations: [makeAlignmentObservation(generation: 8, note: 60, seconds: 0.5)],
        performanceStart: .init(seconds: 0),
        activeTickRange: 0 ..< 1_920,
        generation: 9,
        includeMissing: false
    )
    let outsideRange = engine.align(
        plan: plan,
        observations: [makeAlignmentObservation(generation: 9, note: 60, seconds: 0.5)],
        performanceStart: .init(seconds: 0),
        activeTickRange: 0 ..< 960,
        generation: 9,
        includeMissing: false
    )

    #expect(exact.links.contains {
        if case let .aligned(score, _, _) = $0 { score.eventID == event.id } else { false }
    })
    #expect(wrong.links.contains { if case .extra = $0 { true } else { false } })
    #expect(stale.links.isEmpty)
    #expect(outsideRange.links.contains { if case .extra = $0 { true } else { false } })
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
func chordSpreadUsesCurrentOccurrenceAndRespectsArpeggioProvenance() throws {
    let repeatedEvents = [
        makeAlignmentEvent(sourceID: makeAlignmentSourceID(ordinal: 0), occurrenceIndex: 0),
        makeAlignmentEvent(sourceID: makeAlignmentSourceID(ordinal: 1), occurrenceIndex: 0, midiNote: 64),
        makeAlignmentEvent(sourceID: makeAlignmentSourceID(ordinal: 0), occurrenceIndex: 1, onTick: 960),
        makeAlignmentEvent(
            sourceID: makeAlignmentSourceID(ordinal: 1),
            occurrenceIndex: 1,
            midiNote: 64,
            onTick: 960
        ),
    ]
    let repeated = PerformanceAlignmentEngine().align(
        plan: makeAlignmentPlan(noteEvents: repeatedEvents),
        observations: [
            makeAlignmentObservation(generation: 1, note: 60, seconds: 0),
            makeAlignmentObservation(generation: 1, note: 64, seconds: 0.08),
            makeAlignmentObservation(generation: 1, note: 60, seconds: 1),
            makeAlignmentObservation(generation: 1, note: 64, seconds: 1.08),
        ],
        performanceStart: .init(seconds: 0)
    )
    let spreads = repeated.links.flatMap { link -> [TimeInterval] in
        guard case let .aligned(_, _, evidence) = link else { return [] }
        return evidence.compactMap {
            $0.dimension == .chordSpread ? $0.deviationSeconds : nil
        }
    }
    #expect(spreads.count == 4)
    #expect(spreads.allSatisfy { abs($0 - 0.08) < 0.000_001 })

    let arpeggio = ScorePerformanceProvenance(kind: .arpeggio, sourceIdentity: "arp", detail: nil)
    let arpeggiatedEvents = [
        makeAlignmentEvent(
            sourceID: makeAlignmentSourceID(ordinal: 2),
            occurrenceIndex: 0,
            timingProvenance: [arpeggio]
        ),
        makeAlignmentEvent(
            sourceID: makeAlignmentSourceID(ordinal: 3),
            occurrenceIndex: 0,
            midiNote: 64,
            timingProvenance: [arpeggio]
        ),
    ]
    let arpeggiated = PerformanceAlignmentEngine().align(
        plan: makeAlignmentPlan(noteEvents: arpeggiatedEvents),
        observations: [
            makeAlignmentObservation(generation: 1, note: 60, seconds: 0),
            makeAlignmentObservation(generation: 1, note: 64, seconds: 0.4),
        ],
        performanceStart: .init(seconds: 0)
    )
    let arpeggioEvidence = try #require(arpeggiated.links.compactMap { link -> PerformanceAlignmentEvidence? in
        guard case let .aligned(_, _, evidence) = link else { return nil }
        return evidence.first { $0.dimension == .chordSpread }
    }.first)
    #expect(arpeggioEvidence.status == .notObserved)
    #expect(arpeggioEvidence.cost == nil)
    #expect(arpeggioEvidence.deviationSeconds == nil)
}

@Test
func chordSpreadDoesNotBorrowOnsetsAcrossSourcesOrRepeatedOccurrences() {
    let events = [
        makeAlignmentEvent(sourceID: makeAlignmentSourceID(ordinal: 0), occurrenceIndex: 0),
        makeAlignmentEvent(
            sourceID: makeAlignmentSourceID(ordinal: 1),
            occurrenceIndex: 0,
            midiNote: 64
        ),
        makeAlignmentEvent(
            sourceID: makeAlignmentSourceID(ordinal: 0),
            occurrenceIndex: 1,
            onTick: 960
        ),
        makeAlignmentEvent(
            sourceID: makeAlignmentSourceID(ordinal: 1),
            occurrenceIndex: 1,
            midiNote: 64,
            onTick: 960
        ),
    ]
    let plan = makeAlignmentPlan(noteEvents: events)
    let splitSources = PerformanceAlignmentEngine().align(
        plan: plan,
        observations: [
            makeAlignmentObservation(generation: 1, note: 60, seconds: 0, sourceID: "midi:left"),
            makeAlignmentObservation(generation: 1, note: 64, seconds: 0.08, sourceID: "midi:right"),
        ],
        performanceStart: .init(seconds: 0)
    )
    let splitOccurrences = PerformanceAlignmentEngine().align(
        plan: plan,
        observations: [
            makeAlignmentObservation(generation: 1, note: 60, seconds: 0),
            makeAlignmentObservation(generation: 1, note: 64, seconds: 1.08),
        ],
        performanceStart: .init(seconds: 0)
    )

    for alignment in [splitSources, splitOccurrences] {
        let chordEvidence = alignment.links.compactMap { link -> PerformanceAlignmentEvidence? in
            guard case let .aligned(_, _, evidence) = link else { return nil }
            return evidence.first { $0.dimension == .chordSpread }
        }
        #expect(chordEvidence.count == 2)
        #expect(chordEvidence.allSatisfy { $0.status == .notObserved })
    }
}

@Test
func unisonChordSpreadUsesDistinctObservations() {
    let left = makeAlignmentEvent(
        sourceID: makeAlignmentSourceID(ordinal: 0),
        occurrenceIndex: 0,
        handAssignment: .init(hand: .left, provenance: .score)
    )
    let right = makeAlignmentEvent(
        sourceID: makeAlignmentSourceID(ordinal: 1),
        occurrenceIndex: 0,
        handAssignment: .init(hand: .right, provenance: .score)
    )
    let result = PerformanceAlignmentEngine().align(
        plan: makeAlignmentPlan(noteEvents: [left, right]),
        observations: [
            makeAlignmentObservation(
                generation: 1,
                seconds: 0,
                capabilities: .handContact,
                hand: .left
            ),
            makeAlignmentObservation(
                generation: 1,
                seconds: 0.2,
                capabilities: .handContact,
                hand: .right
            ),
        ],
        performanceStart: .init(seconds: 0)
    )
    let spreads = result.links.compactMap { link -> TimeInterval? in
        guard case let .aligned(_, _, evidence) = link else { return nil }
        return evidence.first { $0.dimension == .chordSpread }?.deviationSeconds
    }

    #expect(spreads.count == 2)
    #expect(spreads.allSatisfy { abs($0 - 0.2) < 0.000_001 })
}

@Test
func ambiguityConsumesOneMissingCandidate() {
    let first = makeAlignmentEvent(
        sourceID: makeAlignmentSourceID(ordinal: 0),
        occurrenceIndex: 0
    )
    let second = makeAlignmentEvent(
        sourceID: makeAlignmentSourceID(ordinal: 1),
        occurrenceIndex: 0
    )
    let result = PerformanceAlignmentEngine().align(
        plan: makeAlignmentPlan(noteEvents: [first, second]),
        observations: [makeAlignmentObservation(generation: 1, seconds: 0)],
        performanceStart: .init(seconds: 0)
    )

    #expect(result.links.filter { if case .ambiguous = $0 { true } else { false } }.count == 1)
    #expect(result.links.filter { if case .missing = $0 { true } else { false } }.count == 1)
}

@Test
func globalAssignmentDoesNotStealScarceCandidate() {
    let first = makeAlignmentEvent(
        sourceID: makeAlignmentSourceID(ordinal: 0),
        occurrenceIndex: 0,
        onTick: 0
    )
    let second = makeAlignmentEvent(
        sourceID: makeAlignmentSourceID(ordinal: 1),
        occurrenceIndex: 0,
        onTick: 960
    )
    let result = PerformanceAlignmentEngine(configuration: .init(
        candidateWindowSeconds: 0.7
    )).align(
        plan: makeAlignmentPlan(noteEvents: [first, second]),
        observations: [
            makeAlignmentObservation(generation: 1, seconds: 0.6),
            makeAlignmentObservation(generation: 1, seconds: 1),
        ],
        performanceStart: .init(seconds: 0)
    )
    let aligned = result.links.compactMap { link -> ScorePerformanceNoteEventID? in
        guard case let .aligned(score, _, _) = link else { return nil }
        return score.eventID
    }

    #expect(Set(aligned) == Set([first.id, second.id]))
    #expect(result.links.contains { if case .extra = $0 { true } else { false } } == false)
    #expect(result.links.contains { if case .missing = $0 { true } else { false } } == false)
}

@Test
func unavailableCapabilitiesNeverFilterCandidatesOrContributeCosts() throws {
    let unavailable = PerformanceInputCapabilities(
        pitch: .observed,
        onset: .unavailable,
        release: .unavailable,
        velocity: .unavailable,
        controllers: .unavailable,
        polyphony: .unavailable,
        hand: .unavailable,
        finger: .unavailable,
        position: .unavailable,
        confidence: .unavailable
    )
    let left = makeAlignmentEvent(
        sourceID: makeAlignmentSourceID(ordinal: 0),
        occurrenceIndex: 0,
        handAssignment: .init(hand: .left, provenance: .score)
    )
    let right = makeAlignmentEvent(
        sourceID: makeAlignmentSourceID(ordinal: 1),
        occurrenceIndex: 0,
        handAssignment: .init(hand: .right, provenance: .score)
    )
    let controller = ScorePerformanceControllerEvent(
        sourceDirectionID: nil,
        performedOccurrenceIndex: 0,
        tick: 0,
        controllerNumber: 64,
        value: 127,
        outputCapabilityRequirement: .continuousControlChange
    )
    let plan = makeAlignmentPlan(noteEvents: [left, right], controllerEvents: [controller])
    let note = makeAlignmentObservation(
        generation: 1,
        note: 60,
        seconds: 0.2,
        capabilities: unavailable,
        hand: .left
    )
    let capableNote = makeAlignmentObservation(generation: 1, note: 72, seconds: 0)
    let unsupportedController = makeAlignmentObservation(
        generation: 1,
        seconds: 0,
        event: .controller(.controlChange(number: 64, value: .init(midi1: 127))),
        capabilities: unavailable
    )

    let result = PerformanceAlignmentEngine().align(
        plan: plan,
        observations: [note, capableNote, unsupportedController],
        performanceStart: .init(seconds: 0)
    )

    guard case let .ambiguous(_, candidates) = result.links.first else {
        Issue.record("Unavailable hand evidence must not filter unison candidates")
        return
    }
    #expect(candidates.count == 2)
    #expect(candidates.allSatisfy { candidate in
        candidate.evidence.contains {
            $0.dimension == .onset
                && $0.status == .notObserved
                && $0.cost == nil
                && $0.deviationSeconds == nil
        } && candidate.evidence.contains {
            $0.dimension == .chordSpread
                && $0.status == .notObserved
                && $0.cost == nil
                && $0.deviationSeconds == nil
        } && candidate.evidence.contains {
            $0.dimension == .hand && $0.status == .notObserved && $0.cost == nil
        }
    })
    #expect(result.controllerLinks == [.missing(score: .init(event: controller))])
}

@Test
func unknownHandEvidenceDoesNotFilterKnownHandCandidates() throws {
    let left = makeAlignmentEvent(
        sourceID: makeAlignmentSourceID(ordinal: 0),
        occurrenceIndex: 0,
        handAssignment: .init(hand: .left, provenance: .score)
    )
    let right = makeAlignmentEvent(
        sourceID: makeAlignmentSourceID(ordinal: 1),
        occurrenceIndex: 0,
        handAssignment: .init(hand: .right, provenance: .score)
    )
    let result = PerformanceAlignmentEngine().align(
        plan: makeAlignmentPlan(noteEvents: [left, right]),
        observations: [makeAlignmentObservation(
            generation: 1,
            seconds: 0,
            capabilities: .handContact,
            hand: .unknown
        )],
        performanceStart: .init(seconds: 0)
    )

    let candidateGroups = result.links.compactMap { link -> [PerformanceAlignmentCandidate]? in
        guard case let .ambiguous(_, candidates) = link else { return nil }
        return candidates
    }
    let candidates = try #require(candidateGroups.first)
    #expect(candidates.count == 2)
    #expect(candidates.allSatisfy { candidate in
        candidate.evidence.contains {
            $0.dimension == .hand && $0.status == .notObserved && $0.cost == nil
        }
    })
}

@Test
func duplicateControllerScoreReferencesAreCollapsed() {
    let controller = ScorePerformanceControllerEvent(
        sourceDirectionID: nil,
        performedOccurrenceIndex: 0,
        tick: 0,
        controllerNumber: 64,
        value: 127,
        outputCapabilityRequirement: .continuousControlChange
    )
    let observation = makeAlignmentObservation(
        generation: 1,
        note: 0,
        seconds: 0,
        event: .controller(.controlChange(number: 64, value: .init(midi1: 127)))
    )
    let plan = makeAlignmentPlan(
        noteEvents: [],
        controllerEvents: [controller, controller]
    )

    let offline = PerformanceAlignmentEngine().align(
        plan: plan,
        observations: [observation],
        performanceStart: .init(seconds: 0),
        generation: 1
    )
    #expect(offline.controllerLinks.count == 1)
    #expect(offline.controllerLinks.contains {
        if case .aligned = $0 { true } else { false }
    })

    var online = IncrementalPerformanceAligner()
    online.start(plan: plan, generation: 1, performanceStart: .init(seconds: 0))
    _ = online.append(observation)
    #expect(online.finish() == offline)
}

@Test
func controllerAssignmentMaximizesCoverageBeforeMinimizingCost() {
    let first = ScorePerformanceControllerEvent(
        sourceDirectionID: nil,
        performedOccurrenceIndex: 0,
        tick: 960,
        controllerNumber: 64,
        value: 0,
        outputCapabilityRequirement: .continuousControlChange
    )
    let second = ScorePerformanceControllerEvent(
        sourceDirectionID: nil,
        performedOccurrenceIndex: 0,
        tick: 1_920,
        controllerNumber: 64,
        value: 127,
        outputCapabilityRequirement: .continuousControlChange
    )
    let engine = PerformanceAlignmentEngine(
        configuration: .init(candidateWindowSeconds: 0.7)
    )
    let onlyFirst = makeAlignmentObservation(
        generation: 1,
        note: 0,
        seconds: 0.4,
        event: .controller(.controlChange(number: 64, value: .init(midi1: 0)))
    )
    let flexible = makeAlignmentObservation(
        generation: 1,
        note: 0,
        seconds: 1.4,
        event: .controller(.controlChange(number: 64, value: .init(midi1: 127)))
    )

    let result = engine.align(
        plan: makeAlignmentPlan(noteEvents: [], controllerEvents: [first, second]),
        observations: [onlyFirst, flexible],
        performanceStart: .init(seconds: 0)
    )

    #expect(result.controllerLinks.filter {
        if case .aligned = $0 { true } else { false }
    }.count == 2)
    #expect(result.controllerLinks.contains {
        if case .missing = $0 { true } else { false }
    } == false)
    #expect(result.controllerLinks.contains {
        if case .extra = $0 { true } else { false }
    } == false)
}

@Test
func releaseDurationParticipatesInCandidateSelection() throws {
    let short = makeAlignmentEvent(
        sourceID: makeAlignmentSourceID(ordinal: 0),
        occurrenceIndex: 0,
        offTick: 240
    )
    let long = makeAlignmentEvent(
        sourceID: makeAlignmentSourceID(ordinal: 1),
        occurrenceIndex: 0,
        offTick: 960
    )
    let noteOn = makeAlignmentObservation(generation: 1, seconds: 0)
    let noteOff = makeAlignmentObservation(
        generation: 1,
        seconds: 1,
        event: .noteOff(note: 60, releaseVelocity: nil)
    )

    let result = PerformanceAlignmentEngine().align(
        plan: makeAlignmentPlan(noteEvents: [short, long]),
        observations: [noteOn, noteOff],
        performanceStart: .init(seconds: 0)
    )

    guard case let .aligned(score, _, evidence) = result.links.first else {
        Issue.record("Release duration should resolve equal-onset candidates")
        return
    }
    #expect(score.eventID == long.id)
    #expect(evidence.contains {
        $0.dimension == .duration && abs($0.deviationSeconds ?? 1) < 0.000_001
    })
}

@Test
func contactReleasePairingIncludesSourceIdentity() throws {
    let first = makeAlignmentEvent(
        sourceID: makeAlignmentSourceID(ordinal: 0),
        occurrenceIndex: 0,
        midiNote: 60,
        offTick: 960
    )
    let second = makeAlignmentEvent(
        sourceID: makeAlignmentSourceID(ordinal: 1),
        occurrenceIndex: 0,
        midiNote: 64,
        onTick: 96,
        offTick: 1_056
    )
    let firstOn = makeAlignmentObservation(
        generation: 1,
        seconds: 0,
        event: .contact(id: "same", keyCandidate: 60, phase: .started),
        capabilities: .handContact,
        sourceID: "left"
    )
    let secondOn = makeAlignmentObservation(
        generation: 1,
        seconds: 0.1,
        event: .contact(id: "same", keyCandidate: 64, phase: .started),
        capabilities: .handContact,
        sourceID: "right"
    )
    let observations = [
        firstOn,
        secondOn,
        makeAlignmentObservation(
            generation: 1,
            seconds: 1,
            event: .contact(id: "same", keyCandidate: 60, phase: .ended),
            capabilities: .handContact,
            sourceID: "left"
        ),
        makeAlignmentObservation(
            generation: 1,
            seconds: 1.1,
            event: .contact(id: "same", keyCandidate: 64, phase: .ended),
            capabilities: .handContact,
            sourceID: "right"
        ),
    ]

    let result = PerformanceAlignmentEngine().align(
        plan: makeAlignmentPlan(noteEvents: [first, second]),
        observations: observations,
        performanceStart: .init(seconds: 0)
    )
    let durationByObservation: [UUID: TimeInterval] = Dictionary(
        uniqueKeysWithValues: result.links.compactMap { link -> (UUID, TimeInterval)? in
            guard case let .aligned(_, observation, evidence) = link else { return nil }
            guard let duration = evidence.first(where: {
                $0.dimension == .duration
            })?.deviationSeconds else { return nil }
            return (observation.observationID, duration)
        }
    )

    #expect(abs(durationByObservation[firstOn.id] ?? 1) < 0.000_001)
    #expect(abs(durationByObservation[secondOn.id] ?? 1) < 0.000_001)
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
    let noteOn = makeAlignmentObservation(generation: 3, note: 60, seconds: 0.1)
    let noteOff = makeAlignmentObservation(
        generation: 3,
        note: 60,
        seconds: 0.5,
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
    #expect(evidence.contains {
        $0.dimension == .release && abs($0.deviationSeconds ?? 1) < 0.000_001
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

@Test
func handEvidenceDisambiguatesPolyphonicUnisonWithoutUsingStaffAsHand() throws {
    let right = makeAlignmentEvent(
        sourceID: makeAlignmentSourceID(ordinal: 0),
        occurrenceIndex: 0,
        handAssignment: .init(hand: .right, provenance: .score)
    )
    let left = makeAlignmentEvent(
        sourceID: makeAlignmentSourceID(ordinal: 1),
        occurrenceIndex: 0,
        handAssignment: .init(hand: .left, provenance: .teacher)
    )
    let plan = makeAlignmentPlan(noteEvents: [right, left])
    let typed = makeAlignmentObservation(generation: 1, note: 60, seconds: 0, hand: .right)
    let unknown = makeAlignmentObservation(generation: 1, note: 60, seconds: 0)

    let typedResult = PerformanceAlignmentEngine().align(
        plan: plan,
        observations: [typed],
        performanceStart: .init(seconds: 0)
    )
    guard case let .aligned(score, _, evidence) = typedResult.links.first else {
        Issue.record("Expected typed hand to align")
        return
    }
    #expect(score.eventID == right.id)
    #expect(evidence.contains {
        $0.dimension == .voice && $0.status == .notObserved && $0.cost == nil
    })

    let unknownResult = PerformanceAlignmentEngine().align(
        plan: plan,
        observations: [unknown],
        performanceStart: .init(seconds: 0)
    )
    #expect(unknownResult.links.contains { if case .ambiguous = $0 { true } else { false } })
}

@Test
func performedTimeSelectsRepeatedOccurrenceWithoutChangingSourceIdentity() throws {
    let sourceID = makeAlignmentSourceID(ordinal: 0)
    let first = makeAlignmentEvent(sourceID: sourceID, occurrenceIndex: 0, onTick: 0)
    let repeated = makeAlignmentEvent(sourceID: sourceID, occurrenceIndex: 1, onTick: 960)
    let result = PerformanceAlignmentEngine().align(
        plan: makeAlignmentPlan(noteEvents: [first, repeated]),
        observations: [makeAlignmentObservation(generation: 1, note: 60, seconds: 1)],
        performanceStart: .init(seconds: 0)
    )

    guard case let .aligned(score, _, _) = result.links.first else {
        Issue.record("Expected repeated occurrence to align")
        return
    }
    #expect(score.sourceNoteID == sourceID)
    #expect(score.performedOccurrenceIndex == 1)
}

@Test
func incrementalAlignerRejectsStaleOutOfOrderAndSystemPlaybackAndResetsLifecycle() throws {
    let event = makeAlignmentEvent(sourceID: makeAlignmentSourceID(ordinal: 0), occurrenceIndex: 0)
    let plan = makeAlignmentPlan(noteEvents: [event])
    var aligner = IncrementalPerformanceAligner(
        configuration: .init(maximumBufferedObservations: 32, commitHorizonSeconds: 0.1)
    )
    aligner.start(plan: plan, generation: 4, performanceStart: .init(seconds: 0))

    #expect(aligner.append(makeAlignmentObservation(generation: 3, seconds: 0)) == nil)
    let accepted = makeAlignmentObservation(generation: 4, seconds: 0.2)
    #expect(aligner.append(accepted) != nil)
    #expect(aligner.append(makeAlignmentObservation(generation: 4, seconds: 0.1)) == nil)
    #expect(aligner.append(makeAlignmentObservation(
        generation: 4,
        seconds: 0.3,
        role: .systemPlayback
    )) == nil)
    #expect(aligner.finish()?.links.contains { if case .aligned = $0 { true } else { false } } == true)
    #expect(aligner.state == .finished)

    aligner.reset()
    #expect(aligner.state == .idle)
}

@Test
func incrementalAlignerRejectsPreStartObservationBeforeItPinsSourceGeneration() throws {
    let event = makeAlignmentEvent(sourceID: makeAlignmentSourceID(ordinal: 0), occurrenceIndex: 0)
    let plan = makeAlignmentPlan(noteEvents: [event])
    var aligner = IncrementalPerformanceAligner()
    aligner.start(plan: plan, generation: nil, performanceStart: .init(seconds: 10))

    #expect(aligner.append(makeAlignmentObservation(generation: 3, seconds: 9.9)) == nil)
    let current = makeAlignmentObservation(generation: 4, seconds: 10)
    #expect(aligner.append(current) != nil)
    let finished = aligner.finish()
    let result = try #require(finished)

    #expect(result.sourceGeneration == 4)
    #expect(result.links.contains { link in
        guard case let .aligned(_, observation, _) = link else { return false }
        return observation.observationID == current.id
    })
}

@Test
func incrementalAlignerWaitsForRepeatCandidateWindowsBeforeCommitting() throws {
    let sourceID = makeAlignmentSourceID(ordinal: 0)
    let firstEvent = makeAlignmentEvent(sourceID: sourceID, occurrenceIndex: 0)
    let repeatedEvent = makeAlignmentEvent(
        sourceID: sourceID,
        occurrenceIndex: 1,
        onTick: 960
    )
    let plan = makeAlignmentPlan(noteEvents: [firstEvent, repeatedEvent])
    let early = makeAlignmentObservation(generation: 1, seconds: 0.6)
    let clockAdvance = makeAlignmentObservation(generation: 1, note: 72, seconds: 0.91)
    let repeated = makeAlignmentObservation(generation: 1, seconds: 1)
    let observations = [early, clockAdvance, repeated]
    var incremental = IncrementalPerformanceAligner()
    incremental.start(plan: plan, generation: 1, performanceStart: .init(seconds: 0))
    for observation in observations {
        _ = incremental.append(observation)
    }

    let finished = incremental.finish()
    let online = try #require(finished)
    let offline = PerformanceAlignmentEngine().align(
        plan: plan,
        observations: observations,
        performanceStart: .init(seconds: 0),
        generation: 1
    )

    #expect(online == offline)
}

@Test
func incrementalTrimPreservesCompleteFinalFacts() throws {
    let plan = makeAlignmentPlan(noteEvents: [])
    var aligner = IncrementalPerformanceAligner(
        configuration: .init(maximumBufferedObservations: 32, commitHorizonSeconds: 0.3)
    )
    aligner.start(plan: plan, generation: 1, performanceStart: .init(seconds: 0))
    var observations: [PerformanceObservation] = []
    for index in 0 ..< 40 {
        let observation = makeAlignmentObservation(
            generation: 1,
            note: 60 + index % 2,
            seconds: Double(index) * 0.01
        )
        observations.append(observation)
        _ = aligner.append(observation)
    }

    let finished = aligner.finish()
    let online = try #require(finished)
    let offline = PerformanceAlignmentEngine().align(
        plan: plan,
        observations: observations,
        performanceStart: .init(seconds: 0),
        generation: 1
    )

    #expect(aligner.bufferedObservationCount == 32)
    #expect(aligner.discardedObservationCount == 8)
    #expect(online == offline)
}

@Test
func bufferTrimDiscardsIrrelevantControllersBeforeFreezingProvisionalNotes() throws {
    let first = makeAlignmentEvent(
        sourceID: makeAlignmentSourceID(ordinal: 0),
        occurrenceIndex: 0,
        onTick: 0
    )
    let second = makeAlignmentEvent(
        sourceID: makeAlignmentSourceID(ordinal: 1),
        occurrenceIndex: 0,
        onTick: 960
    )
    let plan = makeAlignmentPlan(noteEvents: [first, second])
    let engine = PerformanceAlignmentEngine(
        configuration: .init(candidateWindowSeconds: 0.7)
    )
    var aligner = IncrementalPerformanceAligner(
        engine: engine,
        configuration: .init(maximumBufferedObservations: 32, commitHorizonSeconds: 10)
    )
    aligner.start(plan: plan, generation: 1, performanceStart: .init(seconds: 0))
    let flexible = makeAlignmentObservation(generation: 1, seconds: 0.6)
    _ = aligner.append(flexible)
    for index in 0 ..< 32 {
        _ = aligner.append(makeAlignmentObservation(
            generation: 1,
            seconds: 0.61 + Double(index) * 0.001,
            event: .controller(.programChange(program: index))
        ))
    }
    let scarce = makeAlignmentObservation(generation: 1, seconds: 1)
    _ = aligner.append(scarce)

    let finished = aligner.finish()
    let online = try #require(finished)
    let offline = engine.align(
        plan: plan,
        observations: [flexible, scarce],
        performanceStart: .init(seconds: 0),
        generation: 1
    )
    let onlineAligned = online.links.compactMap { link -> ScorePerformanceNoteEventID? in
        guard case let .aligned(score, _, _) = link else { return nil }
        return score.eventID
    }
    let offlineAligned = offline.links.compactMap { link -> ScorePerformanceNoteEventID? in
        guard case let .aligned(score, _, _) = link else { return nil }
        return score.eventID
    }

    #expect(Set(onlineAligned) == Set(offlineAligned))
    #expect(aligner.bufferedObservationCount == 2)
}

@Test
func committedScoreEventsCannotBeRematched() throws {
    let first = makeAlignmentEvent(
        sourceID: makeAlignmentSourceID(ordinal: 0),
        occurrenceIndex: 0,
        onTick: 0
    )
    let second = makeAlignmentEvent(
        sourceID: makeAlignmentSourceID(ordinal: 1),
        occurrenceIndex: 0,
        onTick: 960
    )
    let plan = makeAlignmentPlan(noteEvents: [first, second])
    var aligner = IncrementalPerformanceAligner(
        configuration: .init(maximumBufferedObservations: 32, commitHorizonSeconds: 0.3)
    )
    aligner.start(plan: plan, generation: 1, performanceStart: .init(seconds: 0))
    _ = aligner.append(makeAlignmentObservation(generation: 1, seconds: 0))
    for index in 0 ..< 33 {
        _ = aligner.append(makeAlignmentObservation(
            generation: 1,
            seconds: 0.31 + Double(index) * 0.001,
            event: .controller(.programChange(program: index))
        ))
    }
    _ = aligner.append(makeAlignmentObservation(generation: 1, seconds: 0.4))

    let finished = aligner.finish()
    let result = try #require(finished)
    let aligned = result.links.compactMap { link -> ScorePerformanceNoteEventID? in
        guard case let .aligned(score, _, _) = link else { return nil }
        return score.eventID
    }

    #expect(Set(aligned) == Set([first.id, second.id]))
}

@Test
func evictedOpenNoteKeepsReleaseEvidence() throws {
    let event = makeAlignmentEvent(
        sourceID: makeAlignmentSourceID(ordinal: 0),
        occurrenceIndex: 0,
        offTick: 960
    )
    let plan = makeAlignmentPlan(noteEvents: [event])
    var aligner = IncrementalPerformanceAligner(
        configuration: .init(maximumBufferedObservations: 32, commitHorizonSeconds: 0.3)
    )
    aligner.start(plan: plan, generation: 1, performanceStart: .init(seconds: 0))
    _ = aligner.append(makeAlignmentObservation(generation: 1, seconds: 0))
    for index in 0 ..< 32 {
        _ = aligner.append(makeAlignmentObservation(
            generation: 1,
            seconds: 0.31 + Double(index) * 0.001,
            event: .controller(.programChange(program: index))
        ))
    }
    _ = aligner.append(makeAlignmentObservation(
        generation: 1,
        seconds: 1,
        event: .noteOff(note: 60, releaseVelocity: nil)
    ))

    let finished = aligner.finish()
    let result = try #require(finished)
    let durations = result.links.compactMap { link -> TimeInterval? in
        guard case let .aligned(_, _, evidence) = link else { return nil }
        return evidence.first { $0.dimension == .duration }?.deviationSeconds
    }
    let duration = try #require(durations.first)
    #expect(abs(duration) < 0.000_001)
}

@Test
func alignmentRejectsStaleAndSystemPlaybackAcrossNotesReleasesAndControllers() throws {
    let note = makeAlignmentEvent(sourceID: makeAlignmentSourceID(ordinal: 0), occurrenceIndex: 0)
    let controller = ScorePerformanceControllerEvent(
        sourceDirectionID: nil,
        performedOccurrenceIndex: 0,
        tick: 0,
        controllerNumber: 64,
        value: 80,
        outputCapabilityRequirement: .continuousControlChange
    )
    let plan = makeAlignmentPlan(noteEvents: [note], controllerEvents: [controller])
    let accepted = makeAlignmentObservation(generation: 2, note: 60, seconds: 0)
    let staleRelease = makeAlignmentObservation(
        generation: 1,
        note: 60,
        seconds: 2,
        event: .noteOff(note: 60, releaseVelocity: nil)
    )
    let stalePedal = makeAlignmentObservation(
        generation: 1,
        note: 0,
        seconds: 0,
        event: .controller(.controlChange(number: 64, value: .init(midi1: 80)))
    )
    let playback = makeAlignmentObservation(
        generation: 2,
        note: 61,
        seconds: 0,
        role: .systemPlayback
    )

    let result = PerformanceAlignmentEngine().align(
        plan: plan,
        observations: [accepted, staleRelease, stalePedal, playback],
        performanceStart: .init(seconds: 0),
        generation: 2
    )

    #expect(result.links.filter { if case .aligned = $0 { true } else { false } }.count == 1)
    #expect(result.links.contains { if case .extra = $0 { true } else { false } } == false)
    let releaseEvidence = result.links.flatMap { link -> [PerformanceAlignmentEvidence] in
        guard case let .aligned(_, _, evidence) = link else { return [] }
        return evidence.filter { $0.dimension == .release || $0.dimension == .duration }
    }
    #expect(releaseEvidence.allSatisfy { $0.deviationSeconds == nil })
    #expect(result.controllerLinks == [.missing(score: .init(event: controller))])
}

@Test
func recordedTakeReplayUsesSameIncrementalStateMachineAsOnlineAlignment() throws {
    let event = makeAlignmentEvent(sourceID: makeAlignmentSourceID(ordinal: 0), occurrenceIndex: 0)
    let plan = makeAlignmentPlan(noteEvents: [event])
    let observation = makeAlignmentObservation(generation: 2, note: 60, seconds: 0)
    let take = RecordingTake(
        name: "take",
        metadata: .init(scoreIdentity: plan.sourceScoreIdentity, inputSources: []),
        events: [.init(time: 0, kind: .noteOn(midi: 60, velocity: 90), observation: observation)]
    )
    var online = IncrementalPerformanceAligner()
    online.start(plan: plan, generation: 2, performanceStart: .init(seconds: 0))
    _ = online.append(observation)
    let offline = try RecordedTakeAligner().alignResult(take: take, plan: plan)

    #expect(online.finish() == offline.global)
}

@Test
func recordedTakeAlignmentValidatesScoreAndReportsGlobalSegmentDiagnostics() throws {
    let sourceID = makeAlignmentSourceID(ordinal: 0)
    let first = makeAlignmentEvent(sourceID: sourceID, occurrenceIndex: 0, onTick: 0)
    let repeated = makeAlignmentEvent(sourceID: sourceID, occurrenceIndex: 1, onTick: 960)
    let plan = makeAlignmentPlan(noteEvents: [first, repeated])
    let events = [
        RecordingTakeEvent(
            time: 0,
            kind: .noteOn(midi: 60, velocity: 90),
            observation: makeAlignmentObservation(generation: 1, note: 60, seconds: 0)
        ),
        RecordingTakeEvent(
            time: 1,
            kind: .noteOn(midi: 60, velocity: 90),
            observation: makeAlignmentObservation(generation: 1, note: 60, seconds: 1)
        ),
    ]
    let take = RecordingTake(
        name: "repeats",
        metadata: .init(scoreIdentity: plan.sourceScoreIdentity, inputSources: []),
        events: events
    )

    let result = try RecordedTakeAligner().alignResult(
        take: take,
        plan: plan,
        segmentTickRanges: [0 ..< 480, 960 ..< 1_440]
    )
    #expect(result.diagnostics.alignedCount == 2)
    #expect(result.diagnostics.segmentCount == 2)
    #expect(result.diagnostics.performedOccurrenceCount == 2)
    #expect(result.segments.allSatisfy { segment in
        segment.alignment.links.contains { if case .aligned = $0 { true } else { false } }
    })

    let otherIdentity = ScorePerformanceSourceIdentity(
        songID: UUID(),
        scoreRevision: "other",
        logicalInstrumentID: "piano"
    )
    let wrongTake = RecordingTake(
        name: "wrong",
        metadata: .init(scoreIdentity: otherIdentity, inputSources: []),
        events: events
    )
    #expect(throws: RecordedTakeAlignmentError.scoreIdentityMismatch) {
        try RecordedTakeAligner().alignResult(take: wrongTake, plan: plan)
    }
    let unattributed = RecordingTake(name: "unattributed", events: events)
    #expect(throws: RecordedTakeAlignmentError.scoreIdentityMismatch) {
        try RecordedTakeAligner().alignResult(take: unattributed, plan: plan)
    }
    let untyped = RecordingTake(
        name: "untyped",
        metadata: .init(scoreIdentity: plan.sourceScoreIdentity, inputSources: []),
        events: [.init(time: 0, kind: .noteOn(midi: 60, velocity: 90))]
    )
    #expect(throws: RecordedTakeAlignmentError.missingObservation) {
        try RecordedTakeAligner().alignResult(take: untyped, plan: plan)
    }
}

@Test
func recordedTakeReplaySortsEventsAndKeepsSegmentUpperBoundsExclusive() throws {
    let first = makeAlignmentEvent(
        sourceID: makeAlignmentSourceID(ordinal: 0),
        occurrenceIndex: 0,
        onTick: 0
    )
    let second = makeAlignmentEvent(
        sourceID: makeAlignmentSourceID(ordinal: 1),
        occurrenceIndex: 0,
        midiNote: 64,
        onTick: 480
    )
    let plan = makeAlignmentPlan(noteEvents: [first, second])
    let take = RecordingTake(
        name: "out-of-order",
        metadata: .init(scoreIdentity: plan.sourceScoreIdentity, inputSources: []),
        events: [
            .init(
                time: 0.5,
                kind: .noteOn(midi: 64, velocity: 90),
                observation: makeAlignmentObservation(generation: 1, note: 64, seconds: 0.5)
            ),
            .init(
                time: 0,
                kind: .noteOn(midi: 60, velocity: 90),
                observation: makeAlignmentObservation(generation: 1, note: 60, seconds: 0)
            ),
        ]
    )

    let result = try RecordedTakeAligner().alignResult(
        take: take,
        plan: plan,
        segmentTickRanges: [0 ..< 480, 480 ..< 960]
    )

    #expect(result.diagnostics.alignedCount == 2)
    #expect(result.segments.count == 2)
    #expect(result.segments.allSatisfy { segment in
        segment.alignment.links.filter { if case .aligned = $0 { true } else { false } }.count == 1
            && segment.alignment.links.contains { if case .extra = $0 { true } else { false } } == false
    })
}

@Test
func recordedTakeAlignmentDoesNotTrimLongControllerSeries() throws {
    let event = makeAlignmentEvent(sourceID: makeAlignmentSourceID(ordinal: 0), occurrenceIndex: 0)
    let plan = makeAlignmentPlan(noteEvents: [event])
    let eventCount = 4_097
    let events = (0 ..< eventCount).map { index in
        let seconds = Double(index) / 1_000
        let observation = makeAlignmentObservation(
            generation: 1,
            note: 0,
            seconds: seconds,
            event: .controller(.controlChange(number: 64, value: .init(midi1: index % 128)))
        )
        return RecordingTakeEvent(
            time: seconds,
            kind: .controlChange(controller: 64, value: index % 128),
            observation: observation
        )
    }
    let take = RecordingTake(
        name: "long-controller-series",
        metadata: .init(scoreIdentity: plan.sourceScoreIdentity, inputSources: []),
        events: events
    )

    let result = try RecordedTakeAligner().alignResult(take: take, plan: plan)

    #expect(result.global.controllerLinks.count == eventCount)
    #expect(result.diagnostics.controllerLinkCount == eventCount)
}

@Test
func insufficientEvidenceIsUnknownAndLiveLinksStayProvisionalUntilCommitHorizon() throws {
    let event = makeAlignmentEvent(sourceID: makeAlignmentSourceID(ordinal: 0), occurrenceIndex: 0)
    let plan = makeAlignmentPlan(noteEvents: [event])
    let unavailable = PerformanceInputCapabilities(
        pitch: .unavailable,
        onset: .observed,
        release: .unavailable,
        velocity: .unavailable,
        controllers: .unavailable,
        polyphony: .unavailable,
        hand: .unavailable,
        finger: .unavailable,
        position: .unavailable,
        confidence: .unavailable
    )
    let unknown = makeAlignmentObservation(
        generation: 1,
        note: 60,
        seconds: 0,
        capabilities: unavailable
    )
    let unknownResult = PerformanceAlignmentEngine().align(
        plan: plan,
        observations: [unknown],
        performanceStart: .init(seconds: 0)
    )
    #expect(unknownResult.links.contains {
        if case .unknown(_, .unavailablePitchEvidence) = $0 { true } else { false }
    })

    var incremental = IncrementalPerformanceAligner(
        configuration: .init(maximumBufferedObservations: 32, commitHorizonSeconds: 0.2)
    )
    incremental.start(plan: plan, generation: 1, performanceStart: .init(seconds: 0))
    let firstSnapshot = incremental.append(makeAlignmentObservation(
        generation: 1,
        note: 60,
        seconds: 0
    ))
    let first = try #require(firstSnapshot)
    #expect(first.links.contains { if case .provisional = $0 { true } else { false } })

    _ = incremental.append(makeAlignmentObservation(
        generation: 1,
        note: 72,
        seconds: 0.5
    ))
    let finalSnapshot = incremental.finish()
    let final = try #require(finalSnapshot)
    #expect(final.links.contains { if case .aligned = $0 { true } else { false } })
    #expect(final.links.contains { if case .provisional = $0 { true } else { false } } == false)
}

@Test
func goldenAlignmentReplaysCoverRequiredPerformanceCases() throws {
    let corpus = try PerformanceAlignmentReplayCorpusLoader().load()
    let requiredCoverage: Set<String> = [
        "correct", "early", "late", "serial-chord", "extra", "missing",
        "repeat", "unison", "pedal", "ambiguous",
    ]
    #expect(Set(corpus.cases.flatMap(\.coverage)) == requiredCoverage)

    for replayCase in corpus.cases {
        let noteEvents = replayCase.notes.map { note in
            makeAlignmentEvent(
                sourceID: makeAlignmentSourceID(ordinal: note.sourceOrdinal),
                occurrenceIndex: note.occurrenceIndex,
                midiNote: note.midiNote,
                onTick: note.onTick
            )
        }
        let controllerEvents = replayCase.observations.contains { $0.kind == .pedal }
            ? [ScorePerformanceControllerEvent(
                sourceDirectionID: nil,
                performedOccurrenceIndex: 0,
                tick: 0,
                controllerNumber: 64,
                value: 80,
                outputCapabilityRequirement: .continuousControlChange
            )]
            : []
        let plan = makeAlignmentPlan(noteEvents: noteEvents, controllerEvents: controllerEvents)
        let observations = replayCase.observations.map { observation in
            let event: PerformanceObservation.Event = switch observation.kind {
            case .noteOn:
                .noteOn(note: observation.midiNote ?? 0, velocity: .init(midi1: 90))
            case .pedal:
                .controller(.controlChange(number: 64, value: .init(midi1: observation.value ?? 0)))
            }
            return makeAlignmentObservation(
                generation: 1,
                note: observation.midiNote ?? 0,
                seconds: observation.seconds,
                event: event
            )
        }
        let alignment = PerformanceAlignmentEngine().align(
            plan: plan,
            observations: observations,
            performanceStart: .init(seconds: 0),
            generation: 1
        )
        let counts = alignment.links.reduce(into: [String: Int]()) { counts, link in
            let key = switch link {
            case .aligned: "aligned"
            case .missing: "missing"
            case .extra: "extra"
            case .ambiguous: "ambiguous"
            case .unknown: "unknown"
            case .provisional: "provisional"
            }
            counts[key, default: 0] += 1
        }
        let expected = replayCase.expected
        #expect(counts["aligned", default: 0] == expected.aligned, "case=\(replayCase.id)")
        #expect(counts["missing", default: 0] == expected.missing, "case=\(replayCase.id)")
        #expect(counts["extra", default: 0] == expected.extra, "case=\(replayCase.id)")
        #expect(counts["ambiguous", default: 0] == expected.ambiguous, "case=\(replayCase.id)")
        #expect(counts["unknown", default: 0] == 0, "case=\(replayCase.id)")
        #expect(counts["provisional", default: 0] == 0, "case=\(replayCase.id)")
        #expect(alignment.controllerLinks.count == expected.controllerLinks, "case=\(replayCase.id)")
        #expect(Set(noteEvents.map(\.performedOccurrenceIndex)).sorted() == expected.performedOccurrences)

        let evidence = alignment.links.flatMap { link -> [PerformanceAlignmentEvidence] in
            guard case let .aligned(_, _, evidence) = link else { return [] }
            return evidence
        }
        #expect(expected.requiresEarly == evidence.contains {
            $0.dimension == .onset && ($0.deviationSeconds ?? 0) < -0.05
        }, "case=\(replayCase.id)")
        #expect(expected.requiresLate == evidence.contains {
            $0.dimension == .onset && ($0.deviationSeconds ?? 0) > 0.05
        }, "case=\(replayCase.id)")
        #expect(expected.requiresChordSpread == evidence.contains {
            $0.dimension == .chordSpread && abs($0.deviationSeconds ?? 0) > 0.05
        }, "case=\(replayCase.id)")
    }
}

@Test
func incrementalAlignmentKeepsLongScoreReplayBounded() {
    let eventCount = 512
    let events = (0 ..< eventCount).map { index in
        makeAlignmentEvent(
            sourceID: makeAlignmentSourceID(ordinal: index),
            occurrenceIndex: 0,
            midiNote: 48 + index % 36,
            onTick: index * 120
        )
    }
    let plan = makeAlignmentPlan(noteEvents: events)
    var aligner = IncrementalPerformanceAligner(
        configuration: .init(maximumBufferedObservations: 32, commitHorizonSeconds: 0.2)
    )
    aligner.start(plan: plan, generation: 1, performanceStart: .init(seconds: 0))

    let elapsed = ContinuousClock().measure {
        for event in events {
            _ = aligner.append(makeAlignmentObservation(
                generation: 1,
                note: event.midiNote,
                seconds: Double(event.performedOnTick) / 960
            ))
        }
    }
    #expect(aligner.bufferedObservationCount <= 32)
    #expect(aligner.discardedObservationCount == eventCount - 32)
    _ = aligner.finish()

    // ponytail: broad regression ceiling; replace with Instruments metrics if this debug-simulator check exceeds 5 seconds.
    #expect(elapsed < .seconds(5))
}

private func makeAlignmentObservation(
    id: UUID = UUID(),
    generation: UInt64,
    note: Int = 60,
    seconds: TimeInterval = 12,
    event: PerformanceObservation.Event? = nil,
    capabilities: PerformanceInputCapabilities? = nil,
    hand: ScoreHand? = nil,
    role: PerformanceObservation.Source.Role = .userPerformance,
    sourceID: String = "midi:test"
) -> PerformanceObservation {
    PerformanceObservation(
        id: id,
        source: .init(
            kind: .midi1,
            id: sourceID,
            generation: generation,
            capabilities: capabilities,
            role: role
        ),
        timing: PerformanceClockReading(
            host: .init(seconds: seconds + 0.1),
            source: nil,
            correctedHost: .init(seconds: seconds),
            mapping: nil,
            provenance: .latencyEstimate
        ),
        event: event ?? .noteOn(note: note, velocity: .init(midi1: 90)),
        hand: hand
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
    onTick: Int = 0,
    offTick: Int? = nil,
    handAssignment: ScoreHandAssignment = .init(hand: .right, provenance: .score),
    timingProvenance: [ScorePerformanceProvenance] = []
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
        writtenOffTick: offTick ?? onTick + 480,
        performedOnTick: onTick,
        performedOffTick: offTick ?? onTick + 480,
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
        handAssignment: handAssignment,
        fingerings: [],
        timingProvenance: timingProvenance
    )
}
