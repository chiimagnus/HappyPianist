import Foundation

struct PerformanceAssessmentService: Sendable {
    struct Configuration: Equatable, Sendable {
        // ponytail: P11-T7 will replace these baseline tolerances with the capability-aware rubric.
        let onsetToleranceSeconds: TimeInterval
        let chordSpreadToleranceSeconds: TimeInterval
        let tempoRelativeTolerance: Double

        init(
            onsetToleranceSeconds: TimeInterval = 0.08,
            chordSpreadToleranceSeconds: TimeInterval = 0.08,
            tempoRelativeTolerance: Double = 0.2
        ) {
            self.onsetToleranceSeconds = Self.nonnegative(onsetToleranceSeconds, fallback: 0.08)
            self.chordSpreadToleranceSeconds = Self.nonnegative(chordSpreadToleranceSeconds, fallback: 0.08)
            self.tempoRelativeTolerance = Self.nonnegative(tempoRelativeTolerance, fallback: 0.2)
        }

        private static func nonnegative(_ value: Double, fallback: Double) -> Double {
            value.isFinite ? max(0, value) : fallback
        }
    }

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

    private let configuration: Configuration

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    func assess(
        plan: ScorePerformancePlan,
        alignment: PerformanceAlignment,
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
        let resolvedTickRange = tickRange ?? Self.tickRange(for: activeEvents)
        let timeMap = ScorePerformancePlanTimeMap(plan: plan)

        return PassagePerformanceAssessment(
            planID: plan.id,
            sourceGeneration: alignment.sourceGeneration,
            tickRange: resolvedTickRange,
            rubricVersion: .initial,
            dimensions: dimensions(
                plan: plan,
                events: activeEvents,
                links: activeLinks,
                eventByID: eventByID,
                timeMap: timeMap
            ),
            measures: measureAssessments(
                plan: plan,
                events: activeEvents,
                links: activeLinks,
                passageTickRange: resolvedTickRange,
                timeMap: timeMap
            )
        )
    }

    private func dimensions(
        plan: ScorePerformancePlan,
        events: [ScorePerformanceNoteEvent],
        links: [PerformanceAlignmentLink],
        eventByID: [ScorePerformanceNoteEventID: ScorePerformanceNoteEvent],
        timeMap: ScorePerformancePlanTimeMap
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

        return [
            exactPitchResult(aligned: aligned, links: links),
            extraNotesResult(aligned: aligned, links: links),
            missingNotesResult(aligned: aligned, links: links),
            timingResult(
                dimension: .onset,
                samples: onsetSamples,
                unit: .seconds,
                tolerance: configuration.onsetToleranceSeconds,
                links: links
            ),
            timingResult(
                dimension: .tempoRelativeTiming,
                samples: tempoRelativeSamples,
                unit: .normalized,
                tolerance: configuration.tempoRelativeTolerance,
                links: links
            ),
            chordSpreadResult(events: events, aligned: aligned, links: links),
        ]
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
            guard case let .extra(observation, evidence) = link else { return nil }
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
        tolerance: Double,
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
            passes: samples.allSatisfy { abs($0.value) <= tolerance }
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
                : (samples.allSatisfy { $0.value <= configuration.chordSpreadToleranceSeconds }
                    ? .correct
                    : .incorrect),
            evidenceStatus: hasIncompleteChord ? .insufficient : aggregateStatus(samples.map(\.status)),
            measurement: PerformanceAssessmentMeasurement(value: mean, unit: .seconds),
            sampleCount: samples.count,
            confidence: confidence(for: samples),
            evidence: samples.flatMap(\.evidence)
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
                .unknownObservation(observationID: observation.observationID, reason: .ambiguousKeyCandidate)
            case let .unknown(observation, reason):
                .unknownObservation(observationID: observation.observationID, reason: reason)
            case let .provisional(score, observation, _):
                .note(score: score, observationID: observation.observationID, dimension: dimension)
            case .aligned, .missing, .extra:
                nil
            }
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
        if statuses.contains(.degraded) { return .degraded }
        if statuses.contains(.observed) { return .observed }
        if statuses.contains(.insufficient) { return .insufficient }
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

    private func measureAssessments(
        plan: ScorePerformancePlan,
        events: [ScorePerformanceNoteEvent],
        links: [PerformanceAlignmentLink],
        passageTickRange: Range<Int>,
        timeMap: ScorePerformancePlanTimeMap
    ) -> [MeasurePerformanceAssessment] {
        // ponytail: the plan has no rest-only spans; pass prepared spans if rest assessment becomes relevant.
        let grouped = Dictionary(grouping: events) { event in
            PracticeMeasureOccurrenceID(
                sourceMeasureID: PracticeSourceMeasureID(
                    partID: event.sourceNoteID.partID,
                    sourceMeasureIndex: event.sourceNoteID.sourceMeasureIndex,
                    sourceNumberToken: event.sourceNoteID.sourceMeasureNumberToken
                ),
                occurrenceIndex: event.performedOccurrenceIndex
            )
        }
        return grouped.compactMap { occurrenceID, measureEvents -> MeasurePerformanceAssessment? in
            let eventIDs = Set(measureEvents.map(\.id))
            let lower = max(
                passageTickRange.lowerBound,
                measureEvents.map(\.performedOnTick).min() ?? passageTickRange.lowerBound
            )
            let upper = min(
                passageTickRange.upperBound,
                measureEvents.map(Self.eventUpperTick).max()
                    ?? passageTickRange.upperBound
            )
            guard lower < upper else { return nil }
            let measureLinks = links.filter { Self.belongs($0, toAny: eventIDs) }
            let eventByID = Dictionary(uniqueKeysWithValues: measureEvents.map { ($0.id, $0) })
            return MeasurePerformanceAssessment(
                occurrenceID: occurrenceID,
                tickRange: lower ..< upper,
                dimensions: dimensions(
                    plan: plan,
                    events: measureEvents,
                    links: measureLinks,
                    eventByID: eventByID,
                    timeMap: timeMap
                )
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

    private static func tickRange(for events: [ScorePerformanceNoteEvent]) -> Range<Int> {
        guard let lower = events.map(\.performedOnTick).min() else { return 0 ..< 0 }
        let upper = events.map(Self.eventUpperTick).max() ?? lower
        return lower ..< upper
    }

    private static func eventUpperTick(_ event: ScorePerformanceNoteEvent) -> Int {
        let (nextTick, overflow) = event.performedOnTick.addingReportingOverflow(1)
        return max(overflow ? .max : nextTick, event.performedOffTick)
    }

    private static func isArpeggiated(_ event: ScorePerformanceNoteEvent) -> Bool {
        event.timingProvenance.contains { $0.kind == .arpeggio }
    }
}
