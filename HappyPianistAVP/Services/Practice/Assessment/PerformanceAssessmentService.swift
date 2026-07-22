import Foundation

struct PerformanceAssessmentService: Sendable {
    private struct AlignedNote {
        let score: PerformanceAlignmentScoreReference
        let observation: PerformanceAlignmentObservationReference
        let evidence: [PerformanceAlignmentEvidence]
        let event: ScorePerformanceNoteEvent
    }

    private struct MetricSample {
        let value: Double
        let status: PerformanceAssessmentEvidenceStatus
        let evidence: [PerformanceAssessmentEvidenceLink]
    }

    private struct ArticulationSample {
        let gapSeconds: TimeInterval
        let deviationSeconds: TimeInterval
        let status: PerformanceAssessmentEvidenceStatus
        let evidence: [PerformanceAssessmentEvidenceLink]
    }

    private struct VoiceLane: Hashable {
        let partID: String
        let staff: Int
        let voice: Int
        let occurrenceIndex: Int
    }

    private struct VoicingRole: Hashable {
        let hand: ScoreHand
        let voice: Int
    }

    private struct TimedOnset {
        let tick: Int
        let deviationSeconds: TimeInterval
        let status: PerformanceAssessmentEvidenceStatus
        let evidence: [PerformanceAssessmentEvidenceLink]
    }

    private let rubric: PerformanceAssessmentRubric

    init(rubric: PerformanceAssessmentRubric = PerformanceAssessmentRubric()) {
        self.rubric = rubric
    }

    func assess(
        plan: ScorePerformancePlan,
        alignment: PerformanceAlignment,
        measureSpans: [MusicXMLMeasureSpan],
        inputCapabilities operationalCapabilities: PerformanceInputCapabilities = .unavailable,
        tickRange: Range<Int>? = nil
    ) -> PassagePerformanceAssessment? {
        guard alignment.planID == plan.id else { return nil }

        let activeEvents = plan.noteEvents.filter { event in
            tickRange?.contains(event.performedOnTick) ?? true
        }
        let eventByID = Dictionary(uniqueKeysWithValues: activeEvents.map { ($0.id, $0) })
        let activeEventIDs = Set(eventByID.keys)
        let activeLinks = alignment.links.filter { link in
            Self.belongsToActiveRange(link, eventIDs: activeEventIDs)
        }
        let resolvedTickRange = tickRange ?? Self.tickRange(for: measureSpans, events: activeEvents)
        let activeControllerLinks = alignment.controllerLinks.filter {
            Self.belongsToActiveRange($0, tickRange: tickRange)
        }
        let timeMap = ScorePerformancePlanTimeMap(plan: plan)
        let capabilities = operationalCapabilities.merging(inputCapabilities(
            links: activeLinks,
            controllerLinks: activeControllerLinks
        ))
        let passageDimensions = dimensions(
            plan: plan,
            events: activeEvents,
            links: activeLinks,
            controllerLinks: activeControllerLinks,
            eventByID: eventByID,
            timeMap: timeMap,
            capabilities: capabilities
        )

        return PassagePerformanceAssessment(
            planID: plan.id,
            sourceGeneration: alignment.sourceGeneration,
            tickRange: resolvedTickRange,
            rubricVersion: rubric.version,
            dimensions: passageDimensions,
            measures: measureAssessments(
                plan: plan,
                events: activeEvents,
                links: activeLinks,
                controllerLinks: activeControllerLinks,
                measureSpans: measureSpans,
                operationalCapabilities: operationalCapabilities,
                passageTickRange: resolvedTickRange,
                timeMap: timeMap
            )
        )
    }

    private func dimensions(
        plan: ScorePerformancePlan,
        events: [ScorePerformanceNoteEvent],
        links: [PerformanceAlignmentLink],
        controllerLinks: [PerformanceAlignmentControllerLink],
        eventByID: [ScorePerformanceNoteEventID: ScorePerformanceNoteEvent],
        timeMap: ScorePerformancePlanTimeMap,
        capabilities: PerformanceInputCapabilities
    ) -> [PerformanceAssessmentDimensionResult] {
        let aligned = alignedNotes(links: links, eventByID: eventByID)
        let onsetSamples = aligned.compactMap { note in
            metricSample(for: note, dimension: .onset)
        }
        let tempoRelativeSamples = aligned.compactMap { note -> MetricSample? in
            guard let sample = metricSample(for: note, dimension: .onset) else { return nil }
            let quarterDuration = timeMap.quarterDurationSeconds(
                at: note.event.performedOnTick,
                resolution: plan.resolution
            )
            return MetricSample(
                value: sample.value / quarterDuration,
                status: sample.status,
                evidence: sample.evidence
            )
        }

        let results = [
            exactPitchResult(aligned: aligned, links: links),
            extraNotesResult(aligned: aligned, links: links),
            missingNotesResult(aligned: aligned, links: links),
            timingResult(
                dimension: .onset,
                samples: onsetSamples,
                unit: .seconds,
                links: links
            ),
            timingResult(
                dimension: .tempoRelativeTiming,
                samples: tempoRelativeSamples,
                unit: .normalized,
                links: links
            ),
            chordSpreadResult(
                events: events,
                aligned: aligned,
                links: links
            ),
            durationResult(
                aligned: aligned,
                links: links,
                timeMap: timeMap
            ),
            releaseResult(
                aligned: aligned,
                links: links
            ),
            articulationResult(
                aligned: aligned,
                links: links,
                timeMap: timeMap
            ),
            velocityResult(
                aligned: aligned,
                links: links
            ),
            dynamicContourResult(
                aligned: aligned,
                links: links
            ),
            voicingResult(
                events: events,
                aligned: aligned,
                links: links
            ),
            pedalTimingResult(
                links: controllerLinks
            ),
            pedalValueResult(
                links: controllerLinks
            ),
            tempoContinuityResult(
                plan: plan,
                aligned: aligned,
                timeMap: timeMap
            ),
            phraseContinuityResult(
                plan: plan,
                aligned: aligned
            ),
        ]
        return rubric.select(
            results.map { addingUnresolvedEvidence(to: $0, links: links) },
            capabilities: capabilities
        )
    }

    private func exactPitchResult(
        aligned: [AlignedNote],
        links: [PerformanceAlignmentLink]
    ) -> PerformanceAssessmentDimensionResult {
        let samples = aligned.compactMap { note -> MetricSample? in
            guard let value = note.evidence.first(where: { $0.dimension == .pitch }),
                  value.status != .notObserved,
                  let cost = value.cost
            else { return nil }
            return MetricSample(
                value: cost == 0 ? 1 : 0,
                status: assessmentStatus(value.status, event: note.event),
                evidence: [.note(
                    score: note.score,
                    observationID: note.observation.observationID,
                    dimension: .pitch
                )]
            )
        }
        guard samples.isEmpty == false else {
            return unavailableResult(
                dimension: .exactPitch,
                alignmentDimension: .pitch,
                links: links,
                fallbackEvidence: aligned.map {
                    .note(score: $0.score, observationID: $0.observation.observationID, dimension: .pitch)
                }
            )
        }
        let ratio = samples.map(\.value).reduce(0, +) / Double(samples.count)
        return result(
            dimension: .exactPitch,
            samples: samples,
            measurement: PerformanceAssessmentMeasurement(value: ratio, unit: .ratio),
            passes: ratio == 1
        )
    }

    private func extraNotesResult(
        aligned: [AlignedNote],
        links: [PerformanceAlignmentLink]
    ) -> PerformanceAssessmentDimensionResult {
        var samples = aligned.map { note in
            let evidence = note.evidence.first(where: { $0.dimension == .pitch })
            return MetricSample(
                value: 0,
                status: assessmentStatus(evidence?.status ?? .observed, event: note.event),
                evidence: [.note(
                    score: note.score,
                    observationID: note.observation.observationID,
                    dimension: .pitch
                )]
            )
        }
        samples.append(contentsOf: links.compactMap { link -> MetricSample? in
            guard case let .extra(observation, evidence, _) = link else { return nil }
            return MetricSample(
                value: 1,
                status: assessmentStatus(
                    evidence.first(where: { $0.dimension == .pitch })?.status ?? .observed,
                    event: nil
                ),
                evidence: [.unmatchedObservation(observationID: observation.observationID)]
            )
        })
        guard samples.isEmpty == false else {
            return unavailableResult(
                dimension: .extraNotes,
                alignmentDimension: .pitch,
                links: links
            )
        }
        let count = samples.map(\.value).reduce(0, +)
        return result(
            dimension: .extraNotes,
            samples: samples,
            measurement: PerformanceAssessmentMeasurement(value: count, unit: .count),
            passes: count == 0
        )
    }

    private func missingNotesResult(
        aligned: [AlignedNote],
        links: [PerformanceAlignmentLink]
    ) -> PerformanceAssessmentDimensionResult {
        var samples = aligned.map { note in
            let evidence = note.evidence.first(where: { $0.dimension == .pitch })
            return MetricSample(
                value: 0,
                status: assessmentStatus(evidence?.status ?? .observed, event: note.event),
                evidence: [.note(
                    score: note.score,
                    observationID: note.observation.observationID,
                    dimension: .pitch
                )]
            )
        }
        samples.append(contentsOf: links.compactMap { link -> MetricSample? in
            guard case let .missing(score, evidence) = link else { return nil }
            return MetricSample(
                value: 1,
                status: assessmentStatus(
                    evidence.first(where: { $0.dimension == .pitch })?.status ?? .observed,
                    event: nil
                ),
                evidence: [.note(score: score, observationID: nil, dimension: .pitch)]
            )
        })
        guard samples.isEmpty == false else {
            return unavailableResult(
                dimension: .missingNotes,
                alignmentDimension: .pitch,
                links: links
            )
        }
        let count = samples.map(\.value).reduce(0, +)
        return result(
            dimension: .missingNotes,
            samples: samples,
            measurement: PerformanceAssessmentMeasurement(value: count, unit: .count),
            passes: count == 0
        )
    }

    private func timingResult(
        dimension: PerformanceAssessmentDimension,
        samples: [MetricSample],
        unit: PerformanceAssessmentMeasurementUnit,
        links: [PerformanceAlignmentLink]
    ) -> PerformanceAssessmentDimensionResult {
        guard samples.isEmpty == false else {
            return unavailableResult(
                dimension: dimension,
                alignmentDimension: .onset,
                links: links
            )
        }
        let mean = samples.map(\.value).reduce(0, +) / Double(samples.count)
        return result(
            dimension: dimension,
            samples: samples,
            measurement: PerformanceAssessmentMeasurement(value: mean, unit: unit),
            passes: samples.allSatisfy {
                rubric.accepts($0.value, for: dimension, evidenceStatus: $0.status)
            }
        )
    }

    private func chordSpreadResult(
        events: [ScorePerformanceNoteEvent],
        aligned: [AlignedNote],
        links: [PerformanceAlignmentLink]
    ) -> PerformanceAssessmentDimensionResult {
        let eligibleChords = Dictionary(grouping: events, by: \.performedOnTick)
            .filter { _, chord in
                chord.count > 1 && chord.contains(where: Self.isArpeggiated) == false
            }
        let alignedByTick = Dictionary(grouping: aligned, by: \.event.performedOnTick)
        var samples: [MetricSample] = []
        var hasIncompleteChord = false

        for tick in eligibleChords.keys.sorted() {
            let chordEvents = eligibleChords[tick] ?? []
            let eventIDs = Set(chordEvents.map(\.id))
            let notes = (alignedByTick[tick] ?? []).filter { eventIDs.contains($0.event.id) }
            guard notes.count == chordEvents.count else {
                hasIncompleteChord = true
                continue
            }
            let chordEvidence = notes.compactMap { note -> (AlignedNote, PerformanceAlignmentEvidence)? in
                guard let evidence = note.evidence.first(where: {
                    $0.dimension == .chordSpread && $0.status != .notObserved && $0.deviationSeconds != nil
                }) else { return nil }
                return (note, evidence)
            }
            guard chordEvidence.count == chordEvents.count else {
                hasIncompleteChord = true
                continue
            }
            let spread = chordEvidence.compactMap { $0.1.deviationSeconds }.max() ?? 0
            samples.append(MetricSample(
                value: spread,
                status: aggregateStatus(chordEvidence.map {
                    assessmentStatus($0.1.status, event: $0.0.event)
                }),
                evidence: chordEvidence.map {
                    .note(
                        score: $0.0.score,
                        observationID: $0.0.observation.observationID,
                        dimension: .chordSpread
                    )
                }
            ))
        }

        guard samples.isEmpty == false else {
            return unavailableResult(
                dimension: .chordSpread,
                alignmentDimension: .chordSpread,
                links: links,
                forceInsufficient: hasIncompleteChord
            )
        }
        let mean = samples.map(\.value).reduce(0, +) / Double(samples.count)
        return PerformanceAssessmentDimensionResult(
            dimension: .chordSpread,
            outcome: hasIncompleteChord
                ? .insufficientEvidence
                : (samples.allSatisfy {
                    rubric.accepts($0.value, for: .chordSpread, evidenceStatus: $0.status)
                }
                    ? .correct
                    : .incorrect),
            evidenceStatus: hasIncompleteChord ? .insufficient : aggregateStatus(samples.map(\.status)),
            measurement: PerformanceAssessmentMeasurement(value: mean, unit: .seconds),
            sampleCount: samples.count,
            confidence: confidence(for: samples),
            evidence: samples.flatMap(\.evidence)
        )
    }

    private func durationResult(
        aligned: [AlignedNote],
        links: [PerformanceAlignmentLink],
        timeMap: ScorePerformancePlanTimeMap
    ) -> PerformanceAssessmentDimensionResult {
        let samples = aligned.compactMap { note -> MetricSample? in
            guard let evidence = note.evidence.first(where: { $0.dimension == .duration }),
                  evidence.status != .notObserved,
                  let deviation = evidence.deviationSeconds
            else { return nil }
            let target = timeMap.seconds(at: note.event.performedOffTick)
                - timeMap.seconds(at: note.event.performedOnTick)
            guard target > 0 else { return nil }
            return MetricSample(
                value: max(0, target + deviation) / target,
                status: assessmentStatus(evidence.status, event: note.event),
                evidence: [.note(
                    score: note.score,
                    observationID: note.observation.observationID,
                    dimension: .duration
                )]
            )
        }
        let hasIncompleteEvidence = aligned.contains { note in
            note.evidence.contains {
                $0.dimension == .duration && $0.status != .notObserved && $0.deviationSeconds == nil
            }
        }
        guard samples.isEmpty == false else {
            return unavailableResult(
                dimension: .duration,
                alignmentDimension: .duration,
                links: links,
                fallbackEvidence: evidenceLinks(aligned, dimension: .duration),
                forceInsufficient: hasIncompleteEvidence
            )
        }
        let mean = samples.map(\.value).reduce(0, +) / Double(samples.count)
        return PerformanceAssessmentDimensionResult(
            dimension: .duration,
            outcome: hasIncompleteEvidence
                ? .insufficientEvidence
                : (samples.allSatisfy {
                    rubric.accepts($0.value, for: .duration, evidenceStatus: $0.status)
                }
                    ? .correct
                    : .incorrect),
            evidenceStatus: hasIncompleteEvidence ? .insufficient : aggregateStatus(samples.map(\.status)),
            measurement: PerformanceAssessmentMeasurement(value: mean, unit: .ratio),
            sampleCount: samples.count,
            confidence: confidence(for: samples),
            evidence: samples.flatMap(\.evidence)
        )
    }

    private func releaseResult(
        aligned: [AlignedNote],
        links: [PerformanceAlignmentLink]
    ) -> PerformanceAssessmentDimensionResult {
        let samples = aligned.compactMap { metricSample(for: $0, dimension: .release) }
        let hasIncompleteEvidence = aligned.contains { note in
            note.evidence.contains {
                $0.dimension == .release && $0.status != .notObserved && $0.deviationSeconds == nil
            }
        }
        guard samples.isEmpty == false else {
            return unavailableResult(
                dimension: .release,
                alignmentDimension: .release,
                links: links,
                fallbackEvidence: evidenceLinks(aligned, dimension: .release),
                forceInsufficient: hasIncompleteEvidence
            )
        }
        let mean = samples.map(\.value).reduce(0, +) / Double(samples.count)
        return PerformanceAssessmentDimensionResult(
            dimension: .release,
            outcome: hasIncompleteEvidence
                ? .insufficientEvidence
                : (samples.allSatisfy {
                    rubric.accepts($0.value, for: .release, evidenceStatus: $0.status)
                }
                    ? .correct
                    : .incorrect),
            evidenceStatus: hasIncompleteEvidence ? .insufficient : aggregateStatus(samples.map(\.status)),
            measurement: PerformanceAssessmentMeasurement(value: mean, unit: .seconds),
            sampleCount: samples.count,
            confidence: confidence(for: samples),
            evidence: samples.flatMap(\.evidence)
        )
    }

    private func articulationResult(
        aligned: [AlignedNote],
        links: [PerformanceAlignmentLink],
        timeMap: ScorePerformancePlanTimeMap
    ) -> PerformanceAssessmentDimensionResult {
        let lanes = Dictionary(grouping: aligned) { note in
            VoiceLane(
                partID: note.event.sourceNoteID.partID,
                staff: note.event.staff,
                voice: note.event.voice,
                occurrenceIndex: note.event.performedOccurrenceIndex
            )
        }
        var samples: [ArticulationSample] = []
        var hasIncompleteEvidence = false

        for notes in lanes.values {
            let ordered = notes.sorted { lhs, rhs in
                if lhs.event.performedOnTick != rhs.event.performedOnTick {
                    return lhs.event.performedOnTick < rhs.event.performedOnTick
                }
                return lhs.event.id.description < rhs.event.id.description
            }
            for (current, next) in zip(ordered, ordered.dropFirst()) {
                guard next.event.performedOnTick > current.event.performedOnTick,
                      next.event.writtenOnTick <= current.event.writtenOffTick
                else { continue }
                guard let duration = current.evidence.first(where: { $0.dimension == .duration }),
                      let onset = next.evidence.first(where: { $0.dimension == .onset }),
                      duration.status != .notObserved,
                      onset.status != .notObserved
                else { continue }
                guard let durationDeviation = duration.deviationSeconds else {
                    hasIncompleteEvidence = true
                    continue
                }

                let targetDuration = timeMap.seconds(at: current.event.performedOffTick)
                    - timeMap.seconds(at: current.event.performedOnTick)
                let actualRelease = current.observation.correctedTime.seconds
                    + max(0, targetDuration + durationDeviation)
                let actualGap = next.observation.correctedTime.seconds - actualRelease
                let targetGap = timeMap.seconds(at: next.event.performedOnTick)
                    - timeMap.seconds(at: current.event.performedOffTick)
                samples.append(ArticulationSample(
                    gapSeconds: actualGap,
                    deviationSeconds: actualGap - targetGap,
                    status: aggregateStatus([
                        assessmentStatus(duration.status, event: current.event),
                        assessmentStatus(onset.status, event: next.event),
                    ]),
                    evidence: [
                        .note(
                            score: current.score,
                            observationID: current.observation.observationID,
                            dimension: .duration
                        ),
                        .note(
                            score: next.score,
                            observationID: next.observation.observationID,
                            dimension: .onset
                        ),
                    ]
                ))
            }
        }

        guard samples.isEmpty == false else {
            return unavailableResult(
                dimension: .articulation,
                alignmentDimension: .duration,
                links: links,
                fallbackEvidence: evidenceLinks(aligned, dimension: .duration),
                forceInsufficient: hasIncompleteEvidence
            )
        }
        let meanGap = samples.map(\.gapSeconds).reduce(0, +) / Double(samples.count)
        return PerformanceAssessmentDimensionResult(
            dimension: .articulation,
            outcome: hasIncompleteEvidence
                ? .insufficientEvidence
                : (samples.allSatisfy {
                    rubric.accepts(
                        $0.deviationSeconds,
                        for: .articulation,
                        evidenceStatus: $0.status
                    )
                } ? .correct : .incorrect),
            evidenceStatus: hasIncompleteEvidence
                ? .insufficient
                : aggregateStatus(samples.map(\.status)),
            measurement: PerformanceAssessmentMeasurement(value: meanGap, unit: .seconds),
            sampleCount: samples.count,
            confidence: articulationConfidence(for: samples),
            evidence: samples.flatMap(\.evidence)
        )
    }

    private func velocityResult(
        aligned: [AlignedNote],
        links: [PerformanceAlignmentLink]
    ) -> PerformanceAssessmentDimensionResult {
        let samples = aligned.compactMap { note -> MetricSample? in
            guard let performed = performedVelocity(note) else { return nil }
            return MetricSample(
                value: performed - Double(note.event.velocity),
                status: velocityStatus(note),
                evidence: [.note(
                    score: note.score,
                    observationID: note.observation.observationID,
                    dimension: .velocity
                )]
            )
        }
        let incomplete = hasIncompleteVelocityEvidence(aligned)
        guard samples.isEmpty == false else {
            return unavailableResult(
                dimension: .velocity,
                alignmentDimension: .velocity,
                links: links,
                fallbackEvidence: evidenceLinks(aligned, dimension: .velocity),
                forceInsufficient: incomplete
            )
        }
        let mean = samples.map(\.value).reduce(0, +) / Double(samples.count)
        return PerformanceAssessmentDimensionResult(
            dimension: .velocity,
            outcome: incomplete
                ? .insufficientEvidence
                : (samples.allSatisfy {
                    rubric.accepts($0.value, for: .velocity, evidenceStatus: $0.status)
                }
                    ? .correct
                    : .incorrect),
            evidenceStatus: incomplete ? .insufficient : aggregateStatus(samples.map(\.status)),
            measurement: PerformanceAssessmentMeasurement(value: mean, unit: .midi7Bit),
            sampleCount: samples.count,
            confidence: confidence(for: samples),
            evidence: samples.flatMap(\.evidence)
        )
    }

    private func dynamicContourResult(
        aligned: [AlignedNote],
        links: [PerformanceAlignmentLink]
    ) -> PerformanceAssessmentDimensionResult {
        let lanes = Dictionary(grouping: aligned) { note in
            VoiceLane(
                partID: note.event.sourceNoteID.partID,
                staff: note.event.staff,
                voice: note.event.voice,
                occurrenceIndex: note.event.performedOccurrenceIndex
            )
        }
        var samples: [MetricSample] = []
        var incomplete = false
        for notes in lanes.values {
            let ordered = notes.sorted { lhs, rhs in
                if lhs.event.performedOnTick != rhs.event.performedOnTick {
                    return lhs.event.performedOnTick < rhs.event.performedOnTick
                }
                return lhs.event.id.description < rhs.event.id.description
            }
            for (current, next) in zip(ordered, ordered.dropFirst())
            where next.event.performedOnTick > current.event.performedOnTick {
                guard let currentVelocity = performedVelocity(current),
                      let nextVelocity = performedVelocity(next)
                else {
                    incomplete = incomplete
                        || hasVelocityCapability(current)
                        || hasVelocityCapability(next)
                    continue
                }
                let performedDelta = nextVelocity - currentVelocity
                let targetDelta = Double(next.event.velocity) - Double(current.event.velocity)
                samples.append(MetricSample(
                    value: performedDelta - targetDelta,
                    status: aggregateStatus([velocityStatus(current), velocityStatus(next)]),
                    evidence: [
                        .note(
                            score: current.score,
                            observationID: current.observation.observationID,
                            dimension: .velocity
                        ),
                        .note(
                            score: next.score,
                            observationID: next.observation.observationID,
                            dimension: .velocity
                        ),
                    ]
                ))
            }
        }
        guard samples.isEmpty == false else {
            return unavailableResult(
                dimension: .dynamicContour,
                alignmentDimension: .velocity,
                links: links,
                fallbackEvidence: evidenceLinks(aligned, dimension: .velocity),
                forceInsufficient: incomplete
            )
        }
        let mean = samples.map(\.value).reduce(0, +) / Double(samples.count)
        return PerformanceAssessmentDimensionResult(
            dimension: .dynamicContour,
            outcome: incomplete
                ? .insufficientEvidence
                : (samples.allSatisfy {
                    rubric.accepts($0.value, for: .dynamicContour, evidenceStatus: $0.status)
                }
                    ? .correct
                    : .incorrect),
            evidenceStatus: incomplete ? .insufficient : aggregateStatus(samples.map(\.status)),
            measurement: PerformanceAssessmentMeasurement(value: mean, unit: .midi7Bit),
            sampleCount: samples.count,
            confidence: confidence(for: samples),
            evidence: samples.flatMap(\.evidence)
        )
    }

    private func voicingResult(
        events: [ScorePerformanceNoteEvent],
        aligned: [AlignedNote],
        links: [PerformanceAlignmentLink]
    ) -> PerformanceAssessmentDimensionResult {
        let evidenceStatus: PerformanceAssessmentEvidenceStatus = rubric.usesGenericTarget(for: .voicing)
            ? .degraded
            : .observed
        let eligibleChords = Dictionary(grouping: events, by: \.performedOnTick)
            .filter { _, chord in
                chord.count > 1 && chord.contains(where: Self.isArpeggiated) == false
            }
        let alignedByTick = Dictionary(grouping: aligned, by: \.event.performedOnTick)
        var samples: [MetricSample] = []
        var incomplete = false

        for tick in eligibleChords.keys.sorted() {
            let chordEvents = eligibleChords[tick] ?? []
            let eventIDs = Set(chordEvents.map(\.id))
            let notes = (alignedByTick[tick] ?? []).filter { eventIDs.contains($0.event.id) }
            guard notes.count == chordEvents.count,
                  notes.allSatisfy({ performedVelocity($0) != nil })
            else {
                incomplete = incomplete || notes.contains(where: hasVelocityCapability)
                continue
            }

            let grouped = Dictionary(grouping: notes) { note in
                VoicingRole(hand: explicitVoicingHand(note.event), voice: note.event.voice)
            }
            let values: [(performed: Double, target: Double)]
            if grouped.count > 1 {
                values = grouped.values.map { roleNotes in
                    (
                        performed: roleNotes.compactMap(performedVelocity).reduce(0, +)
                            / Double(roleNotes.count),
                        target: roleNotes.map { Double($0.event.velocity) }.reduce(0, +)
                            / Double(roleNotes.count)
                    )
                }
            } else {
                values = notes.compactMap { note in
                    performedVelocity(note).map { ($0, Double(note.event.velocity)) }
                }
            }
            let performedCenter = values.map(\.performed).reduce(0, +) / Double(values.count)
            let targetCenter = values.map(\.target).reduce(0, +) / Double(values.count)
            let error = values.map {
                abs(($0.performed - performedCenter) - ($0.target - targetCenter))
            }.reduce(0, +) / Double(values.count)

            samples.append(MetricSample(
                value: error,
                status: evidenceStatus,
                evidence: notes.map {
                    .note(
                        score: $0.score,
                        observationID: $0.observation.observationID,
                        dimension: .velocity
                    )
                }
            ))
        }

        guard samples.isEmpty == false else {
            return unavailableResult(
                dimension: .voicing,
                alignmentDimension: .velocity,
                links: links,
                fallbackEvidence: evidenceLinks(aligned, dimension: .velocity),
                forceInsufficient: incomplete
            )
        }
        let mean = samples.map(\.value).reduce(0, +) / Double(samples.count)
        return PerformanceAssessmentDimensionResult(
            dimension: .voicing,
            outcome: incomplete
                ? .insufficientEvidence
                : (samples.allSatisfy {
                    rubric.accepts($0.value, for: .voicing, evidenceStatus: $0.status)
                }
                    ? .correct
                    : .incorrect),
            evidenceStatus: incomplete ? .insufficient : evidenceStatus,
            measurement: PerformanceAssessmentMeasurement(value: mean, unit: .midi7Bit),
            sampleCount: samples.count,
            confidence: confidence(for: samples),
            evidence: samples.flatMap(\.evidence)
        )
    }

    private func pedalTimingResult(
        links: [PerformanceAlignmentControllerLink]
    ) -> PerformanceAssessmentDimensionResult {
        let isApproximation = rubric.usesGenericTarget(for: .pedalTiming)
        var samples: [MetricSample] = []
        var failures: [PerformanceAssessmentEvidenceLink] = []
        var unavailable: [PerformanceAssessmentEvidenceLink] = []
        var alignedByController: [UInt8: [(PerformanceAlignmentControllerScoreReference, MetricSample)]] = [:]

        for link in links {
            switch link {
            case let .aligned(score, observation, deviation, _):
                let sample = MetricSample(
                    value: deviation,
                    status: controllerStatus(observation, isApproximation: isApproximation),
                    evidence: [.controller(score: score, observationID: observation.observationID)]
                )
                samples.append(sample)
                alignedByController[score.controllerNumber, default: []].append((score, sample))
            case let .missing(score):
                failures.append(.controller(score: score, observationID: nil))
            case let .extra(observation):
                failures.append(.unmatchedObservation(observationID: observation.observationID))
            case let .notObserved(score):
                unavailable.append(.controller(score: score, observationID: nil))
            }
        }

        // Adjacent change deltas preserve the sign of pedal overlap/gap without inventing a separate target.
        for controllerLinks in alignedByController.values {
            let ordered = controllerLinks.sorted { $0.0.tick < $1.0.tick }
            for (current, next) in zip(ordered, ordered.dropFirst()) {
                samples.append(MetricSample(
                    value: next.1.value - current.1.value,
                    status: aggregateStatus([current.1.status, next.1.status]),
                    evidence: current.1.evidence + next.1.evidence
                ))
            }
        }

        guard samples.isEmpty == false || failures.isEmpty == false else {
            return PerformanceAssessmentDimensionResult(
                dimension: .pedalTiming,
                outcome: .unknown,
                evidenceStatus: .notObserved,
                sampleCount: 0,
                evidence: unavailable
            )
        }
        let worst = samples.max { abs($0.value) < abs($1.value) }?.value
        return PerformanceAssessmentDimensionResult(
            dimension: .pedalTiming,
            outcome: failures.isEmpty && samples.allSatisfy {
                rubric.accepts($0.value, for: .pedalTiming, evidenceStatus: $0.status)
            } ? .correct : .incorrect,
            evidenceStatus: isApproximation ? .degraded : aggregateStatus(samples.map(\.status) + [.observed]),
            measurement: worst.flatMap {
                PerformanceAssessmentMeasurement(value: $0, unit: .seconds)
            },
            sampleCount: samples.count + failures.count,
            confidence: confidence(for: samples),
            evidence: samples.flatMap(\.evidence) + failures
        )
    }

    private func pedalValueResult(
        links: [PerformanceAlignmentControllerLink]
    ) -> PerformanceAssessmentDimensionResult {
        let isApproximation = rubric.usesGenericTarget(for: .pedalValue)
        var samples: [MetricSample] = []
        var failures: [PerformanceAssessmentEvidenceLink] = []
        var unavailable: [PerformanceAssessmentEvidenceLink] = []

        for link in links {
            switch link {
            case let .aligned(score, observation, _, deviation):
                samples.append(MetricSample(
                    value: deviation,
                    status: controllerStatus(observation, isApproximation: isApproximation),
                    evidence: [.controller(score: score, observationID: observation.observationID)]
                ))
            case let .missing(score):
                failures.append(.controller(score: score, observationID: nil))
            case let .extra(observation):
                failures.append(.unmatchedObservation(observationID: observation.observationID))
            case let .notObserved(score):
                unavailable.append(.controller(score: score, observationID: nil))
            }
        }

        guard samples.isEmpty == false || failures.isEmpty == false else {
            return PerformanceAssessmentDimensionResult(
                dimension: .pedalValue,
                outcome: .unknown,
                evidenceStatus: .notObserved,
                sampleCount: 0,
                evidence: unavailable
            )
        }
        let mean = samples.isEmpty ? nil : samples.map(\.value).reduce(0, +) / Double(samples.count)
        return PerformanceAssessmentDimensionResult(
            dimension: .pedalValue,
            outcome: failures.isEmpty && samples.allSatisfy {
                rubric.accepts($0.value, for: .pedalValue, evidenceStatus: $0.status)
            } ? .correct : .incorrect,
            evidenceStatus: isApproximation ? .degraded : aggregateStatus(samples.map(\.status) + [.observed]),
            measurement: mean.flatMap {
                PerformanceAssessmentMeasurement(value: $0, unit: .normalized)
            },
            sampleCount: samples.count + failures.count,
            confidence: confidence(for: samples),
            evidence: samples.flatMap(\.evidence) + failures
        )
    }

    private func tempoContinuityResult(
        plan: ScorePerformancePlan,
        aligned: [AlignedNote],
        timeMap: ScorePerformancePlanTimeMap
    ) -> PerformanceAssessmentDimensionResult {
        let onsets = timedOnsets(aligned)
        let expressionBoundaries = Set(plan.annotations.compactMap { annotation in
            switch annotation.kind {
            case .tempoWord, .pause, .phrase: annotation.tick
            case .performanceNotation: nil
            }
        })
        let isApproximation = plan.tempoEvents.allSatisfy { $0.sourceDirectionID == nil }
        var samples: [MetricSample] = []

        for index in 0 ..< max(0, onsets.count - 2) {
            let previous = onsets[index]
            let current = onsets[index + 1]
            let next = onsets[index + 2]
            guard hasBoundary(expressionBoundaries, after: previous.tick, through: next.tick) == false else {
                continue
            }
            let firstTarget = timeMap.seconds(at: current.tick) - timeMap.seconds(at: previous.tick)
            let secondTarget = timeMap.seconds(at: next.tick) - timeMap.seconds(at: current.tick)
            guard firstTarget > 0, secondTarget > 0 else { continue }
            let firstRatio = (firstTarget + current.deviationSeconds - previous.deviationSeconds) / firstTarget
            let secondRatio = (secondTarget + next.deviationSeconds - current.deviationSeconds) / secondTarget
            samples.append(MetricSample(
                value: secondRatio - firstRatio,
                status: isApproximation
                    ? .degraded
                    : aggregateStatus([previous.status, current.status, next.status]),
                evidence: previous.evidence + current.evidence + next.evidence
            ))
        }

        guard samples.isEmpty == false else {
            return continuityUnavailableResult(
                dimension: .tempoContinuity,
                onsets: onsets
            )
        }
        let mean = samples.map(\.value).reduce(0, +) / Double(samples.count)
        return result(
            dimension: .tempoContinuity,
            samples: samples,
            measurement: PerformanceAssessmentMeasurement(value: mean, unit: .normalized),
            passes: samples.allSatisfy {
                rubric.accepts($0.value, for: .tempoContinuity, evidenceStatus: $0.status)
            }
        )
    }

    private func phraseContinuityResult(
        plan: ScorePerformancePlan,
        aligned: [AlignedNote]
    ) -> PerformanceAssessmentDimensionResult {
        let phraseAnnotations = plan.annotations.filter { $0.kind == .phrase }
        let phraseBoundaries = Set(phraseAnnotations.map(\.tick))
        let expressionBoundaries = Set(plan.annotations.compactMap { annotation in
            switch annotation.kind {
            case .tempoWord, .pause: annotation.tick
            case .phrase, .performanceNotation: nil
            }
        })
        let genericBaseline = phraseAnnotations.isEmpty
        var samples: [MetricSample] = []

        let lanes = Dictionary(grouping: aligned) { note in
            VoiceLane(
                partID: note.event.sourceNoteID.partID,
                staff: note.event.staff,
                voice: note.event.voice,
                occurrenceIndex: note.event.performedOccurrenceIndex
            )
        }
        for notes in lanes.values {
            let onsets = timedOnsets(notes)
            for index in 0 ..< max(0, onsets.count - 2) {
                let previous = onsets[index]
                let current = onsets[index + 1]
                let next = onsets[index + 2]
                guard hasBoundary(phraseBoundaries, after: previous.tick, through: next.tick) == false,
                      hasBoundary(expressionBoundaries, after: previous.tick, through: next.tick) == false
                else { continue }
                samples.append(MetricSample(
                    value: next.deviationSeconds
                        - (2 * current.deviationSeconds)
                        + previous.deviationSeconds,
                    // ponytail: absent phrase marks use a passage-wide generic baseline, never full-confidence evidence.
                    status: genericBaseline
                        ? .degraded
                        : aggregateStatus([previous.status, current.status, next.status]),
                    evidence: previous.evidence + current.evidence + next.evidence
                ))
            }
        }

        guard samples.isEmpty == false else {
            return continuityUnavailableResult(
                dimension: .phraseContinuity,
                onsets: timedOnsets(aligned)
            )
        }
        let mean = samples.map(\.value).reduce(0, +) / Double(samples.count)
        return result(
            dimension: .phraseContinuity,
            samples: samples,
            measurement: PerformanceAssessmentMeasurement(value: mean, unit: .seconds),
            passes: samples.allSatisfy {
                rubric.accepts($0.value, for: .phraseContinuity, evidenceStatus: $0.status)
            }
        )
    }

    private func alignedNotes(
        links: [PerformanceAlignmentLink],
        eventByID: [ScorePerformanceNoteEventID: ScorePerformanceNoteEvent]
    ) -> [AlignedNote] {
        links.compactMap { link in
            guard case let .aligned(score, observation, evidence) = link,
                  let event = eventByID[score.eventID]
            else { return nil }
            return AlignedNote(score: score, observation: observation, evidence: evidence, event: event)
        }
    }

    private func inputCapabilities(
        links: [PerformanceAlignmentLink],
        controllerLinks: [PerformanceAlignmentControllerLink]
    ) -> PerformanceInputCapabilities {
        var capabilities: [PerformanceInputCapabilities] = links.compactMap { link in
            switch link {
            case let .aligned(_, observation, _),
                 let .extra(observation, _, _),
                 let .ambiguous(observation, _),
                 let .provisional(_, observation, _),
                 let .unknown(observation, _):
                observation.source.capabilities
            case .missing:
                nil
            }
        }
        capabilities.append(contentsOf: controllerLinks.compactMap { link in
            switch link {
            case let .aligned(_, observation, _, _), let .extra(observation):
                observation.source.capabilities
            case .missing, .notObserved:
                nil
            }
        })
        return capabilities.reduce(.unavailable) { $0.merging($1) }
    }

    private func metricSample(
        for note: AlignedNote,
        dimension: PerformanceAlignmentEvidenceDimension
    ) -> MetricSample? {
        guard let evidence = note.evidence.first(where: { $0.dimension == dimension }),
              evidence.status != .notObserved,
              let deviation = evidence.deviationSeconds
        else { return nil }
        return MetricSample(
            value: deviation,
            status: assessmentStatus(evidence.status, event: note.event),
            evidence: [.note(
                score: note.score,
                observationID: note.observation.observationID,
                dimension: dimension
            )]
        )
    }

    private func evidenceLinks(
        _ aligned: [AlignedNote],
        dimension: PerformanceAlignmentEvidenceDimension
    ) -> [PerformanceAssessmentEvidenceLink] {
        aligned.compactMap { note in
            guard note.evidence.contains(where: { $0.dimension == dimension }) else { return nil }
            return .note(
                score: note.score,
                observationID: note.observation.observationID,
                dimension: dimension
            )
        }
    }

    private func timedOnsets(_ aligned: [AlignedNote]) -> [TimedOnset] {
        Dictionary(grouping: aligned, by: \.event.performedOnTick)
            .compactMap { tick, notes -> TimedOnset? in
                let samples = notes.compactMap { note -> MetricSample? in
                    guard let evidence = note.evidence.first(where: { $0.dimension == .onset }),
                          evidence.status != .notObserved,
                          let deviation = evidence.deviationSeconds
                    else { return nil }
                    return MetricSample(
                        value: deviation,
                        status: assessmentStatus(evidence.status, event: note.event),
                        evidence: [.note(
                            score: note.score,
                            observationID: note.observation.observationID,
                            dimension: .onset
                        )]
                    )
                }
                guard samples.isEmpty == false else { return nil }
                return TimedOnset(
                    tick: tick,
                    deviationSeconds: samples.map(\.value).reduce(0, +) / Double(samples.count),
                    status: aggregateStatus(samples.map(\.status)),
                    evidence: samples.flatMap(\.evidence)
                )
            }
            .sorted { $0.tick < $1.tick }
    }

    private func continuityUnavailableResult(
        dimension: PerformanceAssessmentDimension,
        onsets: [TimedOnset]
    ) -> PerformanceAssessmentDimensionResult {
        PerformanceAssessmentDimensionResult(
            dimension: dimension,
            outcome: onsets.isEmpty ? .unknown : .insufficientEvidence,
            evidenceStatus: onsets.isEmpty ? .notObserved : .insufficient,
            sampleCount: 0,
            evidence: onsets.flatMap(\.evidence)
        )
    }

    private func controllerStatus(
        _ observation: PerformanceAlignmentObservationReference,
        isApproximation: Bool
    ) -> PerformanceAssessmentEvidenceStatus {
        guard isApproximation == false else { return .degraded }
        return switch observation.source.capabilities.controllers {
        case .observed: .observed
        case .degraded: .degraded
        case .unavailable: .notObserved
        }
    }

    private func hasBoundary(
        _ boundaries: Set<Int>,
        after lowerTick: Int,
        through upperTick: Int
    ) -> Bool {
        boundaries.contains { lowerTick < $0 && $0 <= upperTick }
    }

    private func performedVelocity(_ note: AlignedNote) -> Double? {
        guard hasVelocityCapability(note), let value = note.observation.onsetVelocity else { return nil }
        return Double(value.rawValue) * 127 / Double(UInt32.max)
    }

    private func hasVelocityCapability(_ note: AlignedNote) -> Bool {
        note.observation.source.capabilities.velocity != .unavailable
    }

    private func hasIncompleteVelocityEvidence(_ aligned: [AlignedNote]) -> Bool {
        aligned.contains { hasVelocityCapability($0) && $0.observation.onsetVelocity == nil }
    }

    private func velocityStatus(_ note: AlignedNote) -> PerformanceAssessmentEvidenceStatus {
        let status = note.evidence.first(where: { $0.dimension == .velocity })?.status
            ?? alignmentStatus(note.observation.source.capabilities.velocity)
        let assessed = assessmentStatus(status, event: note.event)
        return assessed == .observed && note.event.velocityResolution.usesGenericDynamicBaseline
            ? .degraded
            : assessed
    }

    private func alignmentStatus(
        _ capability: PerformanceInputCapabilities.Evidence
    ) -> PerformanceAlignmentEvidenceStatus {
        switch capability {
        case .observed: .observed
        case .degraded: .degraded
        case .unavailable: .notObserved
        }
    }

    private func explicitVoicingHand(_ event: ScorePerformanceNoteEvent) -> ScoreHand {
        if event.handAssignment.hand != .unknown { return event.handAssignment.hand }
        let fingeringHands = Set(event.fingerings.compactMap { fingering -> ScoreHand? in
            switch fingering.provenance {
            case .score, .teacher, .user:
                switch fingering.hand {
                case .left: .left
                case .right: .right
                case .unspecified, .unsupported: nil
                }
            }
        })
        return fingeringHands.count == 1 ? fingeringHands.first ?? .unknown : .unknown
    }

    private func result(
        dimension: PerformanceAssessmentDimension,
        samples: [MetricSample],
        measurement: PerformanceAssessmentMeasurement?,
        passes: Bool
    ) -> PerformanceAssessmentDimensionResult {
        PerformanceAssessmentDimensionResult(
            dimension: dimension,
            outcome: passes ? .correct : .incorrect,
            evidenceStatus: aggregateStatus(samples.map(\.status)),
            measurement: measurement,
            sampleCount: samples.count,
            confidence: confidence(for: samples),
            evidence: samples.flatMap(\.evidence)
        )
    }

    private func unavailableResult(
        dimension: PerformanceAssessmentDimension,
        alignmentDimension: PerformanceAlignmentEvidenceDimension,
        links: [PerformanceAlignmentLink],
        fallbackEvidence: [PerformanceAssessmentEvidenceLink] = [],
        forceInsufficient: Bool = false
    ) -> PerformanceAssessmentDimensionResult {
        let unresolved = unresolvedEvidence(in: links, dimension: alignmentDimension)
        let isInsufficient = forceInsufficient || unresolved.isEmpty == false
        return PerformanceAssessmentDimensionResult(
            dimension: dimension,
            outcome: isInsufficient ? .insufficientEvidence : .unknown,
            evidenceStatus: isInsufficient ? .insufficient : .notObserved,
            sampleCount: 0,
            evidence: unresolved + fallbackEvidence
        )
    }

    private func unresolvedEvidence(
        in links: [PerformanceAlignmentLink],
        dimension: PerformanceAlignmentEvidenceDimension
    ) -> [PerformanceAssessmentEvidenceLink] {
        links.compactMap { link in
            switch link {
            case let .ambiguous(observation, _):
                .ambiguousObservation(observationID: observation.observationID)
            case let .unknown(observation, reason):
                .unknownObservation(observationID: observation.observationID, reason: reason)
            case let .provisional(score, observation, _):
                .note(score: score, observationID: observation.observationID, dimension: dimension)
            case .aligned, .missing, .extra:
                nil
            }
        }
    }

    private func addingUnresolvedEvidence(
        to result: PerformanceAssessmentDimensionResult,
        links: [PerformanceAlignmentLink]
    ) -> PerformanceAssessmentDimensionResult {
        guard result.evidenceStatus != .insufficient,
              let alignmentDimension = alignmentDimension(for: result.dimension)
        else { return result }
        let unresolved = unresolvedEvidence(in: links, dimension: alignmentDimension)
        guard unresolved.isEmpty == false else { return result }
        return PerformanceAssessmentDimensionResult(
            dimension: result.dimension,
            outcome: result.outcome == .incorrect ? .incorrect : .insufficientEvidence,
            evidenceStatus: .insufficient,
            measurement: result.measurement,
            sampleCount: result.sampleCount,
            confidence: result.confidence,
            evidence: result.evidence + unresolved
        )
    }

    private func alignmentDimension(
        for dimension: PerformanceAssessmentDimension
    ) -> PerformanceAlignmentEvidenceDimension? {
        switch dimension {
        case .exactPitch, .extraNotes, .missingNotes:
            .pitch
        case .onset, .tempoRelativeTiming, .tempoContinuity, .phraseContinuity:
            .onset
        case .chordSpread:
            .chordSpread
        case .duration:
            .duration
        case .release:
            .release
        case .articulation:
            .duration
        case .velocity, .dynamicContour, .voicing:
            .velocity
        case .pedalTiming, .pedalValue:
            nil
        }
    }

    private func assessmentStatus(
        _ status: PerformanceAlignmentEvidenceStatus,
        event: ScorePerformanceNoteEvent?
    ) -> PerformanceAssessmentEvidenceStatus {
        if status != .notObserved,
           event?.timingProvenance.contains(where: { $0.kind == .approximation }) == true
        {
            return .degraded
        }
        return switch status {
        case .observed: .observed
        case .degraded: .degraded
        case .notObserved: .notObserved
        }
    }

    private func aggregateStatus(
        _ statuses: [PerformanceAssessmentEvidenceStatus]
    ) -> PerformanceAssessmentEvidenceStatus {
        if statuses.contains(.insufficient) { return .insufficient }
        if statuses.contains(.degraded) { return .degraded }
        if statuses.contains(.observed) { return .observed }
        return .notObserved
    }

    private func confidence(for samples: [MetricSample]) -> Double? {
        guard samples.isEmpty == false else { return nil }
        return samples.map { sample in
            switch sample.status {
            case .observed: 1
            case .degraded: 0.5
            case .notObserved, .insufficient: 0
            }
        }.reduce(0, +) / Double(samples.count)
    }

    private func articulationConfidence(for samples: [ArticulationSample]) -> Double? {
        guard samples.isEmpty == false else { return nil }
        return samples.map { sample in
            switch sample.status {
            case .observed: 1
            case .degraded: 0.5
            case .notObserved, .insufficient: 0
            }
        }.reduce(0, +) / Double(samples.count)
    }

    private func measureAssessments(
        plan: ScorePerformancePlan,
        events: [ScorePerformanceNoteEvent],
        links: [PerformanceAlignmentLink],
        controllerLinks: [PerformanceAlignmentControllerLink],
        measureSpans: [MusicXMLMeasureSpan],
        operationalCapabilities: PerformanceInputCapabilities,
        passageTickRange: Range<Int>,
        timeMap: ScorePerformancePlanTimeMap
    ) -> [MeasurePerformanceAssessment] {
        let activeSpans = measureSpans.filter {
            $0.startTick < passageTickRange.upperBound && $0.endTick > passageTickRange.lowerBound
        }
        let hasSingleMeasure = activeSpans.count == 1
        let unlocalizedDimensions = hasSingleMeasure
            ? []
            : unlocalizedDimensions(links: links, controllerLinks: controllerLinks)
        return activeSpans.compactMap { span -> MeasurePerformanceAssessment? in
            let lower = max(passageTickRange.lowerBound, span.startTick)
            let upper = min(passageTickRange.upperBound, span.endTick)
            guard lower < upper else { return nil }
            let measureEvents = events.filter { (lower ..< upper).contains($0.performedOnTick) }
            let eventIDs = Set(measureEvents.map(\.id))
            let measureLinks = hasSingleMeasure
                ? links
                : links.filter { Self.belongs($0, toAny: eventIDs) }
            let measureControllerLinks = hasSingleMeasure
                ? controllerLinks
                : controllerLinks.filter { Self.belongs($0, tickRange: lower ..< upper) }
            guard measureEvents.isEmpty == false || measureControllerLinks.isEmpty == false else {
                return nil
            }
            let eventByID = Dictionary(uniqueKeysWithValues: measureEvents.map { ($0.id, $0) })
            let measureCapabilities = operationalCapabilities.merging(inputCapabilities(
                links: measureLinks,
                controllerLinks: measureControllerLinks
            ))
            let measureDimensions = dimensions(
                plan: plan,
                events: measureEvents,
                links: measureLinks,
                controllerLinks: measureControllerLinks,
                eventByID: eventByID,
                timeMap: timeMap,
                capabilities: measureCapabilities
            ).filter { unlocalizedDimensions.contains($0.dimension) == false }
            return MeasurePerformanceAssessment(
                occurrenceID: span.occurrenceID,
                tickRange: lower ..< upper,
                dimensions: measureDimensions
            )
        }.sorted { lhs, rhs in
            if lhs.tickRange.lowerBound != rhs.tickRange.lowerBound {
                return lhs.tickRange.lowerBound < rhs.tickRange.lowerBound
            }
            if lhs.occurrenceID.occurrenceIndex != rhs.occurrenceID.occurrenceIndex {
                return lhs.occurrenceID.occurrenceIndex < rhs.occurrenceID.occurrenceIndex
            }
            return lhs.occurrenceID.sourceMeasureID.sourceMeasureIndex
                < rhs.occurrenceID.sourceMeasureID.sourceMeasureIndex
        }
    }

    private func unlocalizedDimensions(
        links: [PerformanceAlignmentLink],
        controllerLinks: [PerformanceAlignmentControllerLink]
    ) -> Set<PerformanceAssessmentDimension> {
        var result: Set<PerformanceAssessmentDimension> = []
        for link in links {
            switch link {
            case .extra:
                result.insert(.extraNotes)
            case let .unknown(observation, _):
                result.formUnion(PerformanceAssessmentDimension.allCases.filter {
                    $0 != .pedalTiming
                        && $0 != .pedalValue
                        && rubric.evidence(for: $0, capabilities: observation.source.capabilities) != .unavailable
                })
            case .aligned, .missing, .ambiguous, .provisional:
                break
            }
        }
        if controllerLinks.contains(where: { if case .extra = $0 { true } else { false } }) {
            result.formUnion([.pedalTiming, .pedalValue])
        }
        return result
    }

    private static func belongsToActiveRange(
        _ link: PerformanceAlignmentLink,
        eventIDs: Set<ScorePerformanceNoteEventID>
    ) -> Bool {
        switch link {
        case let .aligned(score, _, _), let .missing(score, _), let .provisional(score, _, _):
            eventIDs.contains(score.eventID)
        case let .ambiguous(_, candidates):
            candidates.contains { eventIDs.contains($0.score.eventID) }
        case .extra, .unknown:
            true
        }
    }

    private static func belongsToActiveRange(
        _ link: PerformanceAlignmentControllerLink,
        tickRange: Range<Int>?
    ) -> Bool {
        guard let tickRange else { return true }
        return switch link {
        case let .aligned(score, _, _, _), let .missing(score), let .notObserved(score):
            tickRange.contains(score.tick)
        case .extra:
            true
        }
    }

    private static func belongs(
        _ link: PerformanceAlignmentLink,
        toAny eventIDs: Set<ScorePerformanceNoteEventID>
    ) -> Bool {
        switch link {
        case let .aligned(score, _, _), let .missing(score, _), let .provisional(score, _, _):
            eventIDs.contains(score.eventID)
        case let .ambiguous(_, candidates):
            candidates.contains { eventIDs.contains($0.score.eventID) }
        case .extra, .unknown:
            false
        }
    }

    private static func belongs(
        _ link: PerformanceAlignmentControllerLink,
        tickRange: Range<Int>
    ) -> Bool {
        return switch link {
        case let .aligned(score, _, _, _), let .missing(score), let .notObserved(score):
            tickRange.contains(score.tick)
        case .extra:
            false
        }
    }

    private static func tickRange(for events: [ScorePerformanceNoteEvent]) -> Range<Int> {
        guard let lower = events.map(\.performedOnTick).min() else { return 0 ..< 0 }
        let upper = events.map(Self.eventUpperTick).max() ?? lower
        return lower ..< upper
    }

    private static func tickRange(
        for measureSpans: [MusicXMLMeasureSpan],
        events: [ScorePerformanceNoteEvent]
    ) -> Range<Int> {
        guard let first = measureSpans.min(by: { $0.startTick < $1.startTick }),
              let last = measureSpans.max(by: { $0.endTick < $1.endTick }),
              first.startTick < last.endTick
        else {
            return tickRange(for: events)
        }
        return first.startTick ..< last.endTick
    }

    private static func eventUpperTick(_ event: ScorePerformanceNoteEvent) -> Int {
        let (nextTick, overflow) = event.performedOnTick.addingReportingOverflow(1)
        return max(overflow ? .max : nextTick, event.performedOffTick)
    }

    private static func isArpeggiated(_ event: ScorePerformanceNoteEvent) -> Bool {
        event.timingProvenance.contains { $0.kind == .arpeggio }
    }
}
