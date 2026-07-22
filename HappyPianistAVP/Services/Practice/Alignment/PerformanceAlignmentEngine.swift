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

    fileprivate struct TimedNote: Sendable {
        let event: ScorePerformanceNoteEvent
        let seconds: TimeInterval
    }

    struct PreparedPlan: Sendable {
        fileprivate let plan: ScorePerformancePlan
        fileprivate let timeMap: ScorePerformancePlanTimeMap
        fileprivate let activeNotes: [TimedNote]
        fileprivate let chordEventsByTick: [Int: [ScorePerformanceNoteEvent]]
        fileprivate let eventByID: [ScorePerformanceNoteEventID: ScorePerformanceNoteEvent]
        fileprivate let controllerEvents: [ScorePerformanceControllerEvent]

        fileprivate func notes(
            near seconds: TimeInterval,
            window: TimeInterval
        ) -> ArraySlice<TimedNote> {
            let lowerSeconds = seconds - window
            let upperSeconds = seconds + window
            var lower = 0
            var upper = activeNotes.count
            while lower < upper {
                let middle = lower + (upper - lower) / 2
                if activeNotes[middle].seconds < lowerSeconds {
                    lower = middle + 1
                } else {
                    upper = middle
                }
            }
            let start = lower
            upper = activeNotes.count
            while lower < upper {
                let middle = lower + (upper - lower) / 2
                if activeNotes[middle].seconds <= upperSeconds {
                    lower = middle + 1
                } else {
                    upper = middle
                }
            }
            return activeNotes[start ..< lower]
        }
    }

    private let configuration: PerformanceAlignmentConfiguration

    init(configuration: PerformanceAlignmentConfiguration = .init()) {
        self.configuration = configuration
    }

    func performanceSeconds(plan: ScorePerformancePlan, atTick tick: Int) -> TimeInterval {
        ScorePerformancePlanTimeMap(plan: plan).seconds(at: tick)
    }

    func prepare(
        plan: ScorePerformancePlan,
        activeTickRange: Range<Int>? = nil
    ) -> PreparedPlan {
        let timeMap = ScorePerformancePlanTimeMap(plan: plan)
        let activeNotes = plan.noteEvents.compactMap { event -> TimedNote? in
            guard activeTickRange?.contains(event.performedOnTick) ?? true else { return nil }
            return TimedNote(event: event, seconds: timeMap.seconds(at: event.performedOnTick))
        }.sorted { lhs, rhs in
            if lhs.seconds != rhs.seconds { return lhs.seconds < rhs.seconds }
            return lhs.event.id.description < rhs.event.id.description
        }
        return PreparedPlan(
            plan: plan,
            timeMap: timeMap,
            activeNotes: activeNotes,
            chordEventsByTick: Dictionary(grouping: activeNotes.map(\.event), by: \.performedOnTick),
            eventByID: Dictionary(uniqueKeysWithValues: plan.noteEvents.map { ($0.id, $0) }),
            controllerEvents: plan.controllerEvents.filter {
                activeTickRange?.contains($0.tick) ?? true
            }
        )
    }

    func candidates(
        plan: ScorePerformancePlan,
        observations: [PerformanceObservation],
        performanceStart: PerformanceMonotonicInstant,
        activeTickRange: Range<Int>? = nil,
        generation: UInt64? = nil
    ) -> [PerformanceAlignmentCandidateSnapshot] {
        let preparedPlan = prepare(plan: plan, activeTickRange: activeTickRange)
        return candidates(
            preparedPlan: preparedPlan,
            observations: observations,
            performanceStart: performanceStart,
            generation: generation
        )
    }

    private func candidates(
        preparedPlan: PreparedPlan,
        observations: [PerformanceObservation],
        performanceStart: PerformanceMonotonicInstant,
        generation: UInt64?,
        releaseMeasurements: [UUID: ReleaseMeasurement] = [:]
    ) -> [PerformanceAlignmentCandidateSnapshot] {
        let observedOnsets = observations.compactMap { observation -> (Int, TimeInterval)? in
            let capabilities = observation.source.capabilities
            guard observation.source.role != .systemPlayback,
                  generation.map({ observation.source.generation == $0 }) ?? true,
                  capabilities.pitch != .unavailable,
                  capabilities.onset != .unavailable,
                  capabilities.polyphony != .unavailable,
                  let note = observation.alignmentOnsetMIDINote
            else { return nil }
            return (note, max(0, observation.alignmentTimestamp.seconds - performanceStart.seconds))
        }
        let observedOnsetsByPitch = Dictionary(grouping: observedOnsets, by: \.0)
        return observations.map { observation in
            candidateSnapshot(
                for: observation,
                preparedPlan: preparedPlan,
                performanceStart: performanceStart,
                generation: generation,
                observedOnsetsByPitch: observedOnsetsByPitch,
                releaseMeasurement: releaseMeasurements[observation.id]
            )
        }
    }

    func align(
        plan: ScorePerformancePlan,
        observations: [PerformanceObservation],
        performanceStart: PerformanceMonotonicInstant,
        activeTickRange: Range<Int>? = nil,
        generation: UInt64? = nil,
        includeMissing: Bool = true
    ) -> PerformanceAlignment {
        align(
            preparedPlan: prepare(plan: plan, activeTickRange: activeTickRange),
            observations: observations,
            performanceStart: performanceStart,
            generation: generation,
            includeMissing: includeMissing
        )
    }

    func align(
        preparedPlan: PreparedPlan,
        observations: [PerformanceObservation],
        performanceStart: PerformanceMonotonicInstant,
        generation: UInt64? = nil,
        includeMissing: Bool = true
    ) -> PerformanceAlignment {
        let acceptedObservations = observations.filter { observation in
            observation.source.role != .systemPlayback
                && (generation.map { observation.source.generation == $0 } ?? true)
        }
        let relevantObservations = acceptedObservations.filter {
            $0.alignmentOnsetMIDINote != nil || $0.alignmentUnknownReason != nil
        }
        let releaseMeasurements = Self.releaseMeasurements(observations: acceptedObservations)
        let snapshots = candidates(
            preparedPlan: preparedPlan,
            observations: relevantObservations,
            performanceStart: performanceStart,
            generation: generation,
            releaseMeasurements: releaseMeasurements
        )
        var usedEvents: Set<ScorePerformanceNoteEventID> = []
        var links: [PerformanceAlignmentLink] = []
        let observationByID = Dictionary(uniqueKeysWithValues: acceptedObservations.map { ($0.id, $0) })

        for snapshot in snapshots {
            if let observation = observationByID[snapshot.observation.observationID],
               let reason = observation.alignmentUnknownReason
            {
                links.append(.unknown(observation: snapshot.observation, reason: reason))
                continue
            }
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

        if includeMissing {
            links.append(contentsOf: preparedPlan.activeNotes
                .map(\.event)
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
        }

        return PerformanceAlignment(
            planID: preparedPlan.plan.id,
            sourceGeneration: generation ?? acceptedObservations.first?.source.generation ?? 0,
            links: links,
            controllerLinks: controllerLinks(
                scoreEvents: preparedPlan.controllerEvents,
                observations: acceptedObservations,
                performanceStart: performanceStart,
                timeMap: preparedPlan.timeMap
            )
        )
    }

    private func controllerLinks(
        scoreEvents: [ScorePerformanceControllerEvent],
        observations: [PerformanceObservation],
        performanceStart: PerformanceMonotonicInstant,
        timeMap: ScorePerformancePlanTimeMap
    ) -> [PerformanceAlignmentControllerLink] {
        let observed = observations.compactMap { observation -> (PerformanceObservation, Int, UInt8)? in
            guard observation.source.capabilities.controllers != .unavailable,
                  case let .controller(.controlChange(number, value)) = observation.event
            else { return nil }
            guard let controllerNumber = UInt8(exactly: number),
                  MusicXMLPedalController(rawValue: controllerNumber) != nil
            else { return nil }
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
        preparedPlan: PreparedPlan,
        performanceStart: PerformanceMonotonicInstant,
        generation: UInt64?,
        observedOnsetsByPitch: [Int: [(Int, TimeInterval)]],
        releaseMeasurement: ReleaseMeasurement?
    ) -> PerformanceAlignmentCandidateSnapshot {
        let reference = PerformanceAlignmentObservationReference(observation: observation)
        if let generation, observation.source.generation != generation {
            return .init(observation: reference, candidates: [], noCandidateReason: .staleGeneration)
        }
        guard let observedNote = observation.alignmentOnsetMIDINote else {
            return .init(observation: reference, candidates: [], noCandidateReason: .unsupportedObservation)
        }

        guard preparedPlan.activeNotes.isEmpty == false else {
            return .init(observation: reference, candidates: [], noCandidateReason: .outsideActiveRange)
        }

        let observedSeconds = max(0, observation.alignmentTimestamp.seconds - performanceStart.seconds)
        let temporal = Array(preparedPlan.notes(
            near: observedSeconds,
            window: configuration.candidateWindowSeconds
        ))
        guard temporal.isEmpty == false else {
            return .init(observation: reference, candidates: [], noCandidateReason: .noTemporalCandidate)
        }

        let pitchEvidence = observation.source.capabilities.pitch
        guard pitchEvidence != .unavailable else {
            return .init(observation: reference, candidates: [], noCandidateReason: .noPitchCandidate)
        }
        let pitchMatching = pitchEvidence == .observed
            ? temporal.filter { $0.event.midiNote == observedNote }
            : temporal
        let handEvidence = observation.source.capabilities.hand
        let observedHand = handEvidence == .unavailable ? nil : observation.hand
        let matching: [TimedNote]
        if let observedHand {
            matching = pitchMatching.filter { timedNote in
                timedNote.event.handAssignment.hand == .unknown
                    || timedNote.event.handAssignment.hand == observedHand
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

        let candidates = matching.map { timedNote in
            let event = timedNote.event
            let onsetDeviation = observedSeconds - timedNote.seconds
            let chordEvents = preparedPlan.chordEventsByTick[event.performedOnTick] ?? []
            let onsetEvidence = observation.source.capabilities.onset
            let polyphonyEvidence = observation.source.capabilities.polyphony
            let measuresChordSpread = polyphonyEvidence != .unavailable
                && chordEvents.count > 1
                && chordEvents.contains { note in
                    note.timingProvenance.contains { $0.kind == .arpeggio }
                } == false
            let chordSeconds = timedNote.seconds
            let chordOnsets = measuresChordSpread ? chordEvents.compactMap { chordEvent in
                observedOnsetsByPitch[chordEvent.midiNote]?
                    .filter {
                        abs($0.1 - chordSeconds) <= configuration.candidateWindowSeconds
                    }
                    .min { abs($0.1 - chordSeconds) < abs($1.1 - chordSeconds) }?
                    .1
            } : []
            let chordSpread = (chordOnsets.max().flatMap { maximum in
                chordOnsets.min().map { maximum - $0 }
            }) ?? 0
            let pitchCost = event.midiNote == observedNote ? 0 : configuration.pitchMismatchCost
            let onsetCost = onsetEvidence == .unavailable
                ? 0
                : abs(onsetDeviation) * configuration.onsetWeight
            let chordCost = measuresChordSpread
                ? chordSpread * configuration.chordSpreadWeight
                : 0
            let releaseEvidence = Self.releaseEvidence(
                measurement: releaseMeasurement,
                event: event,
                timeMap: preparedPlan.timeMap,
                onsetDeviation: onsetEvidence == .unavailable ? nil : onsetDeviation,
                unmatchedCost: configuration.unmatchedCost
            )
            return PerformanceAlignmentCandidate(
                score: .init(event: event),
                totalCost: pitchCost + onsetCost + chordCost
                    + releaseEvidence.compactMap(\.cost).reduce(0, +),
                evidence: [
                    .init(
                        dimension: .pitch,
                        status: Self.evidenceStatus(pitchEvidence),
                        cost: pitchCost
                    ),
                    .init(
                        dimension: .onset,
                        status: Self.evidenceStatus(onsetEvidence),
                        cost: onsetEvidence == .unavailable ? nil : onsetCost,
                        deviationSeconds: onsetEvidence == .unavailable ? nil : onsetDeviation
                    ),
                    .init(
                        dimension: .chordSpread,
                        status: measuresChordSpread
                            ? Self.evidenceStatus(polyphonyEvidence)
                            : .notObserved,
                        cost: measuresChordSpread ? chordCost : nil,
                        deviationSeconds: measuresChordSpread ? chordSpread : nil
                    ),
                    .init(
                        dimension: .hand,
                        status: observedHand == nil ? .notObserved : Self.evidenceStatus(handEvidence),
                        cost: observedHand.map {
                            event.handAssignment.hand == .unknown || event.handAssignment.hand == $0 ? 0 : 1
                        }
                    ),
                    .init(
                        dimension: .voice,
                        status: .notObserved
                    ),
                    .init(
                        dimension: .occurrence,
                        status: .observed,
                        cost: 0
                    ),
                    .init(
                        dimension: .velocity,
                        status: Self.evidenceStatus(observation.source.capabilities.velocity)
                    ),
                ] + releaseEvidence
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
        struct ContactRoute: Hashable {
            let source: PerformanceObservation.Source
            let id: String
        }
        var openContacts: [ContactRoute: (UUID, TimeInterval, PerformanceInputCapabilities.Evidence)] = [:]
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
                openContacts[ContactRoute(source: observation.source, id: id)] = (
                    observation.id,
                    observation.alignmentTimestamp.seconds,
                    observation.source.capabilities.release
                )
            case let .contact(id, _, .ended):
                guard let started = openContacts.removeValue(
                    forKey: ContactRoute(source: observation.source, id: id)
                ) else { continue }
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
        timeMap: ScorePerformancePlanTimeMap,
        onsetDeviation: TimeInterval?,
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
        let durationDeviation = actual - expectedDuration
        let releaseDeviation = onsetDeviation.map { $0 + durationDeviation }
        return [
                .init(
                    dimension: .release,
                    status: evidenceStatus(capability),
                    cost: releaseDeviation.map(abs) ?? unmatchedCost,
                    deviationSeconds: releaseDeviation
                ),
                .init(
                    dimension: .duration,
                    status: evidenceStatus(capability),
                    cost: abs(durationDeviation),
                    deviationSeconds: durationDeviation
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


    var alignmentUnknownReason: PerformanceAlignmentUnknownReason? {
        switch event {
        case .noteOn where source.capabilities.pitch == .unavailable:
            .unavailablePitchEvidence
        case let .contact(_, keyCandidate, .started) where keyCandidate == nil:
            .ambiguousKeyCandidate
        case .targetAudioDetection:
            .aggregateAudioEvidence
        case .contact, .noteOff, .controller:
            nil
        case .noteOn:
            nil
        }
    }
}

struct ScorePerformancePlanTimeMap: Sendable {
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

    func quarterDurationSeconds(at tick: Int, resolution: ScorePerformanceTickResolution) -> TimeInterval {
        let start = seconds(at: tick)
        let (endTick, overflow) = tick.addingReportingOverflow(max(1, resolution.ticksPerQuarter))
        let end = seconds(at: overflow ? .max : endTick)
        return max(0.000_1, end - start)
    }

    private static func scaled(_ tick: Int, by scale: Double) -> Int {
        let value = Double(max(0, tick)) * scale
        return value >= Double(Int.max) ? .max : Int(value.rounded())
    }
}
