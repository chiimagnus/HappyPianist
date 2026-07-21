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
    private struct ReleaseMeasurement {
        let duration: TimeInterval?
        let capability: PerformanceInputCapabilities.Evidence
    }

    private let configuration: PerformanceAlignmentConfiguration

    init(configuration: PerformanceAlignmentConfiguration = .init()) {
        self.configuration = configuration
    }

    func performanceSeconds(plan: ScorePerformancePlan, atTick tick: Int) -> TimeInterval {
        PlanTimeMap(plan: plan).seconds(at: tick)
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
            guard let note = observation.alignmentOnsetMIDINote else { return nil }
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
            $0.alignmentOnsetMIDINote != nil
        }
        let snapshots = candidates(
            plan: plan,
            observations: noteOnObservations,
            performanceStart: performanceStart,
            activeTickRange: activeTickRange,
            generation: generation
        )
        let releaseMeasurements = Self.releaseMeasurements(
            observations: observations,
        )
        let timeMap = PlanTimeMap(plan: plan)
        let eventByID = Dictionary(uniqueKeysWithValues: plan.noteEvents.map { ($0.id, $0) })
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
            let releaseEvidence = eventByID[best.score.eventID].map { event in
                Self.releaseEvidence(
                    measurement: releaseMeasurements[snapshot.observation.observationID],
                    event: event,
                    timeMap: timeMap,
                    unmatchedCost: configuration.unmatchedCost
                )
            } ?? []
            links.append(.aligned(
                score: best.score,
                observation: snapshot.observation,
                evidence: best.evidence + releaseEvidence
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
            links: links,
            controllerLinks: controllerLinks(
                plan: plan,
                observations: observations,
                performanceStart: performanceStart,
                activeTickRange: activeTickRange,
                timeMap: timeMap
            )
        )
    }

    private func controllerLinks(
        plan: ScorePerformancePlan,
        observations: [PerformanceObservation],
        performanceStart: PerformanceMonotonicInstant,
        activeTickRange: Range<Int>?,
        timeMap: PlanTimeMap
    ) -> [PerformanceAlignmentControllerLink] {
        let scoreEvents = plan.controllerEvents.filter {
            activeTickRange?.contains($0.tick) ?? true
        }
        let observed = observations.compactMap { observation -> (PerformanceObservation, Int, UInt8)? in
            guard case let .controller(.controlChange(number, value)) = observation.event else { return nil }
            return (observation, number, Self.midi7Bit(value))
        }
        guard observations.contains(where: { $0.source.capabilities.controllers != .unavailable }) else {
            return scoreEvents.map { .notObserved(score: .init(event: $0)) }
        }

        var used: Set<UUID> = []
        var links: [PerformanceAlignmentControllerLink] = []
        for scoreEvent in scoreEvents {
            let scoreSeconds = timeMap.seconds(at: scoreEvent.tick)
            let candidate = observed
                .filter { used.contains($0.0.id) == false && $0.1 == Int(scoreEvent.controllerNumber) }
                .map { item in
                    (
                        observation: item.0,
                        value: item.2,
                        deviation: item.0.alignmentTimestamp.seconds
                            - performanceStart.seconds - scoreSeconds
                    )
                }
                .filter { abs($0.deviation) <= configuration.candidateWindowSeconds }
                .min { lhs, rhs in abs(lhs.deviation) < abs(rhs.deviation) }
            guard let candidate else {
                links.append(.missing(score: .init(event: scoreEvent)))
                continue
            }
            used.insert(candidate.observation.id)
            links.append(.aligned(
                score: .init(event: scoreEvent),
                observation: .init(observation: candidate.observation),
                timeDeviationSeconds: candidate.deviation,
                normalizedValueDeviation: abs(Double(candidate.value) - Double(scoreEvent.value)) / 127
            ))
        }
        links.append(contentsOf: observed
            .filter { used.contains($0.0.id) == false }
            .map { .extra(observation: .init(observation: $0.0)) })
        return links
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
        guard let observedNote = observation.alignmentOnsetMIDINote else {
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
        let pitchMatching = pitchEvidence == .observed
            ? temporal.filter { $0.midiNote == observedNote }
            : temporal
        let matching: [ScorePerformanceNoteEvent]
        if let observedHand = observation.hand {
            matching = pitchMatching.filter { event in
                event.handAssignment.hand == .unknown || event.handAssignment.hand == observedHand
            }
        } else {
            matching = pitchMatching
        }
        guard matching.isEmpty == false else {
            return .init(
                observation: reference,
                candidates: [],
                noCandidateReason: pitchMatching.isEmpty ? .noPitchCandidate : .noHandCandidate
            )
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
                    .init(
                        dimension: .hand,
                        status: observation.hand == nil ? .notObserved : .observed,
                        cost: observation.hand.map {
                            event.handAssignment.hand == .unknown || event.handAssignment.hand == $0 ? 0 : 1
                        }
                    ),
                    .init(
                        dimension: .voice,
                        status: .observed,
                        cost: 0
                    ),
                    .init(
                        dimension: .occurrence,
                        status: .observed,
                        cost: 0
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

    private static func releaseMeasurements(
        observations: [PerformanceObservation]
    ) -> [UUID: ReleaseMeasurement] {
        struct Route: Hashable {
            let source: PerformanceObservation.Source
            let channel: Int?
            let group: Int?
            let note: Int
        }
        var open: [Route: [(UUID, TimeInterval, PerformanceInputCapabilities.Evidence)]] = [:]
        var openContacts: [String: (UUID, TimeInterval, PerformanceInputCapabilities.Evidence)] = [:]
        var durationByOnID: [UUID: (TimeInterval, PerformanceInputCapabilities.Evidence)] = [:]
        for observation in observations.sorted(by: { $0.alignmentTimestamp < $1.alignmentTimestamp }) {
            switch observation.event {
            case let .noteOn(note, _):
                let route = Route(
                    source: observation.source,
                    channel: observation.channel,
                    group: observation.group,
                    note: note
                )
                open[route, default: []].append((
                    observation.id,
                    observation.alignmentTimestamp.seconds,
                    observation.source.capabilities.release
                ))
            case let .noteOff(note, _):
                let route = Route(
                    source: observation.source,
                    channel: observation.channel,
                    group: observation.group,
                    note: note
                )
                guard var notes = open[route], notes.isEmpty == false else { continue }
                let noteOn = notes.removeFirst()
                open[route] = notes
                durationByOnID[noteOn.0] = (
                    max(0, observation.alignmentTimestamp.seconds - noteOn.1),
                    noteOn.2
                )
            case let .contact(id, keyCandidate, .started) where keyCandidate != nil:
                openContacts[id] = (
                    observation.id,
                    observation.alignmentTimestamp.seconds,
                    observation.source.capabilities.release
                )
            case let .contact(id, _, .ended):
                guard let started = openContacts.removeValue(forKey: id) else { continue }
                durationByOnID[started.0] = (
                    max(0, observation.alignmentTimestamp.seconds - started.1),
                    started.2
                )
            default:
                continue
            }
        }

        var result: [UUID: ReleaseMeasurement] = [:]
        for observation in observations {
            guard observation.alignmentOnsetMIDINote != nil else { continue }
            let capability = observation.source.capabilities.release
            result[observation.id] = ReleaseMeasurement(
                duration: durationByOnID[observation.id]?.0,
                capability: capability
            )
        }
        return result
    }

    private static func releaseEvidence(
        measurement: ReleaseMeasurement?,
        event: ScorePerformanceNoteEvent,
        timeMap: PlanTimeMap,
        unmatchedCost: Double
    ) -> [PerformanceAlignmentEvidence] {
        let capability = measurement?.capability ?? .unavailable
        guard capability != .unavailable else {
            return [
                .init(dimension: .release, status: .notObserved),
                .init(dimension: .duration, status: .notObserved),
            ]
        }
        guard let actual = measurement?.duration else {
            return [
                .init(dimension: .release, status: evidenceStatus(capability), cost: unmatchedCost),
                .init(dimension: .duration, status: evidenceStatus(capability), cost: unmatchedCost),
            ]
        }
        let expectedDuration = timeMap.seconds(at: event.performedOffTick)
            - timeMap.seconds(at: event.performedOnTick)
        let deviation = actual - expectedDuration
        return [
                .init(
                    dimension: .release,
                    status: evidenceStatus(capability),
                    cost: abs(deviation),
                    deviationSeconds: deviation
                ),
                .init(
                    dimension: .duration,
                    status: evidenceStatus(capability),
                    cost: abs(deviation),
                    deviationSeconds: deviation
                ),
        ]
    }

    private static func midi7Bit(_ value: PerformanceObservation.NormalizedValue) -> UInt8 {
        UInt8(MIDI2ValueMapping.value32To7Bit(value.rawValue))
    }
}

private extension PerformanceObservation {
    var alignmentOnsetMIDINote: Int? {
        switch event {
        case let .noteOn(note, _):
            note
        case let .contact(_, keyCandidate, .started):
            keyCandidate
        default:
            nil
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
