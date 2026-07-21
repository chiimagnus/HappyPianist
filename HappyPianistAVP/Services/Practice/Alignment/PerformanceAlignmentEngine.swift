import Foundation

struct PerformanceAlignmentConfiguration: Equatable, Sendable {
    let candidateWindowSeconds: TimeInterval
    let ambiguityCostTolerance: Double
    let pitchMismatchCost: Double
    let onsetWeight: Double
    let chordSpreadWeight: Double
    let unmatchedCost: Double

    init(
        candidateWindowSeconds: TimeInterval = 1.5,
        ambiguityCostTolerance: Double = 0.01,
        pitchMismatchCost: Double = 4,
        onsetWeight: Double = 1,
        chordSpreadWeight: Double = 0.5,
        unmatchedCost: Double = 5
    ) {
        self.candidateWindowSeconds = candidateWindowSeconds.isFinite
            ? max(0.01, candidateWindowSeconds)
            : 1.5
        self.ambiguityCostTolerance = Self.nonnegative(ambiguityCostTolerance, fallback: 0.01)
        self.pitchMismatchCost = Self.nonnegative(pitchMismatchCost, fallback: 4)
        self.onsetWeight = Self.nonnegative(onsetWeight, fallback: 1)
        self.chordSpreadWeight = Self.nonnegative(chordSpreadWeight, fallback: 0.5)
        self.unmatchedCost = Self.nonnegative(unmatchedCost, fallback: 5)
    }

    private static func nonnegative(_ value: Double, fallback: Double) -> Double {
        value.isFinite ? max(0, value) : fallback
    }
}

struct PerformanceAlignmentEngine: Sendable {
    private let configuration: PerformanceAlignmentConfiguration

    init(configuration: PerformanceAlignmentConfiguration = .init()) {
        self.configuration = configuration
    }

    func candidates(
        plan: ScorePerformancePlan,
        observations: [PerformanceObservation],
        performanceStart: PerformanceMonotonicInstant,
        activeTickRange: Range<Int>? = nil,
        generation: UInt64? = nil
    ) -> [PerformanceAlignmentCandidateSnapshot] {
        let timeMap = PlanTimeMap(plan: plan)
        let observedOnsets = observations.compactMap { observation -> (Int, TimeInterval)? in
            guard case let .noteOn(note, _) = observation.event else { return nil }
            return (note, max(0, observation.alignmentTimestamp.seconds - performanceStart.seconds))
        }
        return observations.map { observation in
            candidateSnapshot(
                for: observation,
                plan: plan,
                timeMap: timeMap,
                performanceStart: performanceStart,
                activeTickRange: activeTickRange,
                generation: generation,
                observedOnsets: observedOnsets
            )
        }
    }

    func align(
        plan: ScorePerformancePlan,
        observations: [PerformanceObservation],
        performanceStart: PerformanceMonotonicInstant,
        activeTickRange: Range<Int>? = nil,
        generation: UInt64? = nil
    ) -> PerformanceAlignment {
        let noteOnObservations = observations.filter {
            if case .noteOn = $0.event { return true }
            return false
        }
        let snapshots = candidates(
            plan: plan,
            observations: noteOnObservations,
            performanceStart: performanceStart,
            activeTickRange: activeTickRange,
            generation: generation
        )
        var usedEvents: Set<ScorePerformanceNoteEventID> = []
        var links: [PerformanceAlignmentLink] = []

        for snapshot in snapshots {
            let available = snapshot.candidates.filter { usedEvents.contains($0.score.eventID) == false }
            guard let best = available.first else {
                links.append(.extra(
                    observation: snapshot.observation,
                    evidence: [.init(
                        dimension: .pitch,
                        status: .observed,
                        cost: configuration.unmatchedCost
                    )]
                ))
                continue
            }
            let tied = available.prefix { candidate in
                candidate.totalCost - best.totalCost <= configuration.ambiguityCostTolerance
            }
            if tied.count > 1 {
                links.append(.ambiguous(observation: snapshot.observation, candidates: Array(tied)))
                continue
            }
            usedEvents.insert(best.score.eventID)
            links.append(.aligned(
                score: best.score,
                observation: snapshot.observation,
                evidence: best.evidence
            ))
        }

        let activeEvents = plan.noteEvents.filter {
            activeTickRange?.contains($0.performedOnTick) ?? true
        }
        links.append(contentsOf: activeEvents
            .filter { usedEvents.contains($0.id) == false }
            .map { event in
                .missing(
                    score: .init(event: event),
                    evidence: [.init(
                        dimension: .pitch,
                        status: .observed,
                        cost: configuration.unmatchedCost
                    )]
                )
            })

        return PerformanceAlignment(
            planID: plan.id,
            sourceGeneration: generation ?? observations.first?.source.generation ?? 0,
            links: links
        )
    }

    private func candidateSnapshot(
        for observation: PerformanceObservation,
        plan: ScorePerformancePlan,
        timeMap: PlanTimeMap,
        performanceStart: PerformanceMonotonicInstant,
        activeTickRange: Range<Int>?,
        generation: UInt64?,
        observedOnsets: [(Int, TimeInterval)]
    ) -> PerformanceAlignmentCandidateSnapshot {
        let reference = PerformanceAlignmentObservationReference(observation: observation)
        if let generation, observation.source.generation != generation {
            return .init(observation: reference, candidates: [], noCandidateReason: .staleGeneration)
        }
        guard case let .noteOn(observedNote, _) = observation.event else {
            return .init(observation: reference, candidates: [], noCandidateReason: .unsupportedObservation)
        }

        let activeNotes = plan.noteEvents.filter { event in
            activeTickRange?.contains(event.performedOnTick) ?? true
        }
        guard activeNotes.isEmpty == false else {
            return .init(observation: reference, candidates: [], noCandidateReason: .outsideActiveRange)
        }

        let observedSeconds = max(0, observation.alignmentTimestamp.seconds - performanceStart.seconds)
        let temporal = activeNotes.filter { event in
            abs(timeMap.seconds(at: event.performedOnTick) - observedSeconds)
                <= configuration.candidateWindowSeconds
        }
        guard temporal.isEmpty == false else {
            return .init(observation: reference, candidates: [], noCandidateReason: .noTemporalCandidate)
        }

        let pitchEvidence = observation.source.capabilities.pitch
        let matching = pitchEvidence == .observed
            ? temporal.filter { $0.midiNote == observedNote }
            : temporal
        guard matching.isEmpty == false else {
            return .init(observation: reference, candidates: [], noCandidateReason: .noPitchCandidate)
        }

        let candidates = matching.map { event in
            let onsetDeviation = observedSeconds - timeMap.seconds(at: event.performedOnTick)
            let chordPitches = Set(plan.noteEvents.lazy
                .filter { $0.performedOnTick == event.performedOnTick }
                .map(\.midiNote))
            let chordOnsets = observedOnsets
                .filter { chordPitches.contains($0.0) }
                .map(\.1)
            let chordSpread = (chordOnsets.max().flatMap { maximum in
                chordOnsets.min().map { maximum - $0 }
            }) ?? 0
            let pitchCost = event.midiNote == observedNote ? 0 : configuration.pitchMismatchCost
            let onsetCost = abs(onsetDeviation) * configuration.onsetWeight
            let chordCost = chordSpread * configuration.chordSpreadWeight
            return PerformanceAlignmentCandidate(
                score: .init(event: event),
                totalCost: pitchCost + onsetCost + chordCost,
                evidence: [
                    .init(
                        dimension: .pitch,
                        status: Self.evidenceStatus(pitchEvidence),
                        cost: pitchCost
                    ),
                    .init(
                        dimension: .onset,
                        status: Self.evidenceStatus(observation.source.capabilities.onset),
                        cost: onsetCost,
                        deviationSeconds: onsetDeviation
                    ),
                    .init(
                        dimension: .chordSpread,
                        status: Self.evidenceStatus(observation.source.capabilities.polyphony),
                        cost: chordCost,
                        deviationSeconds: chordSpread
                    ),
                ]
            )
        }.sorted { lhs, rhs in
            if lhs.totalCost != rhs.totalCost { return lhs.totalCost < rhs.totalCost }
            return lhs.score.eventID.description < rhs.score.eventID.description
        }
        return .init(observation: reference, candidates: candidates, noCandidateReason: nil)
    }

    private static func evidenceStatus(
        _ evidence: PerformanceInputCapabilities.Evidence
    ) -> PerformanceAlignmentEvidenceStatus {
        switch evidence {
        case .observed: .observed
        case .degraded: .degraded
        case .unavailable: .notObserved
        }
    }
}

private struct PlanTimeMap: Sendable {
    private let scale: Double
    private let map: MusicXMLTempoMap

    init(plan: ScorePerformancePlan) {
        let resolution = max(1, plan.resolution.ticksPerQuarter)
        let tickScale = Double(MusicXMLTempoMap.ticksPerQuarter) / Double(resolution)
        scale = tickScale
        map = MusicXMLTempoMap(performanceEvents: plan.tempoEvents.map { event in
            ScorePerformanceTempoEvent(
                sourceDirectionID: event.sourceDirectionID,
                performedOccurrenceIndex: event.performedOccurrenceIndex,
                tick: Self.scaled(event.tick, by: tickScale),
                quarterBPM: event.quarterBPM,
                endTick: event.endTick.map { Self.scaled($0, by: tickScale) },
                endQuarterBPM: event.endQuarterBPM
            )
        })
    }

    func seconds(at tick: Int) -> TimeInterval {
        map.timeSeconds(atTick: Self.scaled(tick, by: scale))
    }

    private static func scaled(_ tick: Int, by scale: Double) -> Int {
        let value = Double(max(0, tick)) * scale
        return value >= Double(Int.max) ? .max : Int(value.rounded())
    }
}
