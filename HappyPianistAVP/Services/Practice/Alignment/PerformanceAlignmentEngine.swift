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

    private struct ObservedOnset {
        let observationID: UUID
        let pitch: Int
        let seconds: TimeInterval
    }

    private struct FlowEdge {
        let to: Int
        let reverseIndex: Int
        var capacity: Int
        let cost: Double
    }

    private struct HeapItem {
        let distance: Double
        let node: Int
    }

    private struct MinHeap {
        private var items: [HeapItem] = []

        mutating func push(_ item: HeapItem) {
            items.append(item)
            var index = items.count - 1
            while index > 0 {
                let parent = (index - 1) / 2
                guard Self.precedes(items[index], items[parent]) else { break }
                items.swapAt(index, parent)
                index = parent
            }
        }

        mutating func pop() -> HeapItem? {
            guard items.isEmpty == false else { return nil }
            if items.count == 1 { return items.removeLast() }
            let result = items[0]
            items[0] = items.removeLast()
            var index = 0
            while true {
                let left = index * 2 + 1
                guard left < items.count else { break }
                let right = left + 1
                let child = right < items.count && Self.precedes(items[right], items[left])
                    ? right
                    : left
                guard Self.precedes(items[child], items[index]) else { break }
                items.swapAt(index, child)
                index = child
            }
            return result
        }

        private static func precedes(_ lhs: HeapItem, _ rhs: HeapItem) -> Bool {
            lhs.distance != rhs.distance ? lhs.distance < rhs.distance : lhs.node < rhs.node
        }
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
        var seenEventIDs: Set<ScorePerformanceNoteEventID> = []
        let uniqueNoteEvents = plan.noteEvents.filter { seenEventIDs.insert($0.id).inserted }
        let activeNotes = uniqueNoteEvents.compactMap { event -> TimedNote? in
            guard activeTickRange?.contains(event.performedOnTick) ?? true else { return nil }
            return TimedNote(event: event, seconds: timeMap.seconds(at: event.performedOnTick))
        }.sorted { lhs, rhs in
            if lhs.seconds != rhs.seconds { return lhs.seconds < rhs.seconds }
            return lhs.event.id.description < rhs.event.id.description
        }
        var seenControllerEvents: Set<PerformanceAlignmentControllerScoreReference> = []
        let controllerEvents = plan.controllerEvents.filter { event in
            (activeTickRange?.contains(event.tick) ?? true)
                && seenControllerEvents.insert(.init(event: event)).inserted
        }
        return PreparedPlan(
            plan: plan,
            timeMap: timeMap,
            activeNotes: activeNotes,
            chordEventsByTick: Dictionary(grouping: activeNotes.map(\.event), by: \.performedOnTick),
            eventByID: Dictionary(uniqueKeysWithValues: uniqueNoteEvents.map { ($0.id, $0) }),
            controllerEvents: controllerEvents
        )
    }

    private func candidates(
        preparedPlan: PreparedPlan,
        observations: [PerformanceObservation],
        performanceStart: PerformanceMonotonicInstant,
        generation: UInt64?,
        releaseMeasurements: [UUID: ReleaseMeasurement] = [:]
    ) -> [PerformanceAlignmentCandidateSnapshot] {
        let observedOnsets = observations.compactMap { observation -> ObservedOnset? in
            let capabilities = observation.source.capabilities
            guard observation.source.role != .systemPlayback,
                  generation.map({ observation.source.generation == $0 }) ?? true,
                  capabilities.pitch != .unavailable,
                  capabilities.onset != .unavailable,
                  capabilities.polyphony != .unavailable,
                  let note = observation.alignmentOnsetMIDINote
            else { return nil }
            return ObservedOnset(
                observationID: observation.id,
                pitch: note,
                seconds: max(0, observation.alignmentTimestamp.seconds - performanceStart.seconds)
            )
        }
        let observedOnsetsByPitch = Dictionary(grouping: observedOnsets, by: \.pitch)
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
        includeMissing: Bool = true,
        reservedScoreEventIDs: Set<ScorePerformanceNoteEventID> = [],
        reservedControllerScores: Set<PerformanceAlignmentControllerScoreReference> = []
    ) -> PerformanceAlignment {
        align(
            preparedPlan: prepare(plan: plan, activeTickRange: activeTickRange),
            observations: observations,
            performanceStart: performanceStart,
            generation: generation,
            includeMissing: includeMissing,
            reservedScoreEventIDs: reservedScoreEventIDs,
            reservedControllerScores: reservedControllerScores
        )
    }

    func align(
        preparedPlan: PreparedPlan,
        observations: [PerformanceObservation],
        performanceStart: PerformanceMonotonicInstant,
        generation: UInt64? = nil,
        includeMissing: Bool = true,
        reservedScoreEventIDs: Set<ScorePerformanceNoteEventID> = [],
        reservedControllerScores: Set<PerformanceAlignmentControllerScoreReference> = []
    ) -> PerformanceAlignment {
        var seenObservationIDs: Set<UUID> = []
        let acceptedObservations = observations.filter { observation in
            observation.source.role != .systemPlayback
                && (generation.map { observation.source.generation == $0 } ?? true)
                && seenObservationIDs.insert(observation.id).inserted
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
        ).map { snapshot in
            PerformanceAlignmentCandidateSnapshot(
                observation: snapshot.observation,
                candidates: snapshot.candidates.filter {
                    reservedScoreEventIDs.contains($0.score.eventID) == false
                },
                noCandidateReason: snapshot.noCandidateReason
            )
        }
        let observationByID = Dictionary(uniqueKeysWithValues: acceptedObservations.map { ($0.id, $0) })
        var ambiguousSnapshots: [PerformanceAlignmentCandidateSnapshot] = []
        let assignableSnapshots = snapshots.filter { snapshot in
            guard observationByID[snapshot.observation.observationID]?.alignmentUnknownReason == nil,
                  let best = snapshot.candidates.first
            else { return false }
            let tied = snapshot.candidates.prefix { candidate in
                candidate.totalCost - best.totalCost <= configuration.ambiguityCostTolerance
            }
            if tied.count > 1 {
                ambiguousSnapshots.append(snapshot)
                return false
            }
            return true
        }
        let assignedEventByObservation = optimalAssignments(assignableSnapshots)
        let assignedEvents = Set(assignedEventByObservation.values)
        let ambiguousCoveredEvents = Self.maximumAmbiguousCoverage(
            snapshots: ambiguousSnapshots,
            excluding: assignedEvents
        )
        let usedEvents = assignedEvents.union(ambiguousCoveredEvents)
        var links: [PerformanceAlignmentLink] = []

        for snapshot in snapshots {
            if let observation = observationByID[snapshot.observation.observationID],
               let reason = observation.alignmentUnknownReason
            {
                links.append(.unknown(observation: snapshot.observation, reason: reason))
                continue
            }
            guard let best = snapshot.candidates.first else {
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
            let tied = snapshot.candidates.prefix { candidate in
                candidate.totalCost - best.totalCost <= configuration.ambiguityCostTolerance
            }
            if tied.count > 1 {
                links.append(.ambiguous(observation: snapshot.observation, candidates: Array(tied)))
                continue
            }
            guard let assignedEvent = assignedEventByObservation[snapshot.observation.observationID],
                  let assigned = snapshot.candidates.first(where: { $0.score.eventID == assignedEvent })
            else {
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
            links.append(.aligned(
                score: assigned.score,
                observation: snapshot.observation,
                evidence: assigned.evidence
            ))
        }

        if includeMissing {
            links.append(contentsOf: preparedPlan.activeNotes
                .map(\.event)
                .filter {
                    usedEvents.contains($0.id) == false
                        && reservedScoreEventIDs.contains($0.id) == false
                }
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
                timeMap: preparedPlan.timeMap,
                reservedScores: reservedControllerScores
            )
        )
    }

    private func optimalAssignments(
        _ snapshots: [PerformanceAlignmentCandidateSnapshot]
    ) -> [UUID: ScorePerformanceNoteEventID] {
        guard snapshots.isEmpty == false else { return [:] }
        let scoreIDs = Array(Set(snapshots.flatMap { $0.candidates.map(\.score.eventID) }))
            .sorted { $0.description < $1.description }
        let scoreIndex = Dictionary(uniqueKeysWithValues: scoreIDs.enumerated().map { ($0.element, $0.offset) })
        let costs = snapshots.map { snapshot in
            snapshot.candidates.compactMap { candidate -> (targetIndex: Int, cost: Double)? in
                guard let index = scoreIndex[candidate.score.eventID] else { return nil }
                return (index, candidate.totalCost)
            }
        }
        return Dictionary(uniqueKeysWithValues: optimalTargetAssignments(
            costs: costs,
            targetCount: scoreIDs.count
        ).map { observationIndex, targetIndex in
            (snapshots[observationIndex].observation.observationID, scoreIDs[targetIndex])
        })
    }

    private func optimalTargetAssignments(
        costs: [[(targetIndex: Int, cost: Double)]],
        targetCount: Int
    ) -> [Int: Int] {
        guard costs.isEmpty == false, targetCount > 0 else { return [:] }
        let source = 0
        let observationOffset = 1
        let targetOffset = observationOffset + costs.count
        let sink = targetOffset + targetCount
        var graph = Array(repeating: [FlowEdge](), count: sink + 1)

        func addEdge(_ from: Int, _ to: Int, _ capacity: Int, _ cost: Double) {
            let forward = FlowEdge(to: to, reverseIndex: graph[to].count, capacity: capacity, cost: cost)
            let reverse = FlowEdge(to: from, reverseIndex: graph[from].count, capacity: 0, cost: -cost)
            graph[from].append(forward)
            graph[to].append(reverse)
        }

        for observationIndex in costs.indices {
            addEdge(source, observationOffset + observationIndex, 1, 0)
            for candidate in costs[observationIndex] {
                addEdge(
                    observationOffset + observationIndex,
                    targetOffset + candidate.targetIndex,
                    1,
                    candidate.cost
                )
            }
        }
        for index in 0 ..< targetCount {
            addEdge(targetOffset + index, sink, 1, 0)
        }

        var potential = Array(repeating: 0.0, count: graph.count)
        while true {
            var distance = Array(repeating: Double.infinity, count: graph.count)
            var previousNode = Array(repeating: -1, count: graph.count)
            var previousEdge = Array(repeating: -1, count: graph.count)
            var heap = MinHeap()
            distance[source] = 0
            heap.push(.init(distance: 0, node: source))

            while let current = heap.pop() {
                guard current.distance <= distance[current.node] else { continue }
                for edgeIndex in graph[current.node].indices {
                    let edge = graph[current.node][edgeIndex]
                    guard edge.capacity > 0 else { continue }
                    let reducedCost = max(0, edge.cost + potential[current.node] - potential[edge.to])
                    let candidateDistance = current.distance + reducedCost
                    guard candidateDistance < distance[edge.to] else { continue }
                    distance[edge.to] = candidateDistance
                    previousNode[edge.to] = current.node
                    previousEdge[edge.to] = edgeIndex
                    heap.push(.init(distance: candidateDistance, node: edge.to))
                }
            }
            guard distance[sink].isFinite else { break }
            for node in graph.indices where distance[node].isFinite {
                potential[node] += distance[node]
            }
            var node = sink
            while node != source {
                let from = previousNode[node]
                let edgeIndex = previousEdge[node]
                guard from >= 0, edgeIndex >= 0 else { break }
                let reverseIndex = graph[from][edgeIndex].reverseIndex
                graph[from][edgeIndex].capacity -= 1
                graph[node][reverseIndex].capacity += 1
                node = from
            }
        }

        var result: [Int: Int] = [:]
        for observationIndex in costs.indices {
            let node = observationOffset + observationIndex
            for edge in graph[node]
            where edge.to >= targetOffset && edge.to < sink && edge.capacity == 0 {
                result[observationIndex] = edge.to - targetOffset
                break
            }
        }
        return result
    }

    private static func maximumAmbiguousCoverage(
        snapshots: [PerformanceAlignmentCandidateSnapshot],
        excluding unavailable: Set<ScorePerformanceNoteEventID>
    ) -> Set<ScorePerformanceNoteEventID> {
        var observationByEvent: [ScorePerformanceNoteEventID: UUID] = [:]
        let snapshotByObservation = Dictionary(uniqueKeysWithValues: snapshots.map {
            ($0.observation.observationID, $0)
        })

        func assign(
            _ snapshot: PerformanceAlignmentCandidateSnapshot,
            visited: inout Set<ScorePerformanceNoteEventID>
        ) -> Bool {
            for candidate in snapshot.candidates where unavailable.contains(candidate.score.eventID) == false {
                let eventID = candidate.score.eventID
                guard visited.insert(eventID).inserted else { continue }
                if let currentObservation = observationByEvent[eventID],
                   let current = snapshotByObservation[currentObservation]
                {
                    guard assign(current, visited: &visited) else { continue }
                }
                observationByEvent[eventID] = snapshot.observation.observationID
                return true
            }
            return false
        }

        for snapshot in snapshots {
            var visited: Set<ScorePerformanceNoteEventID> = []
            _ = assign(snapshot, visited: &visited)
        }
        return Set(observationByEvent.keys)
    }

    private func controllerLinks(
        scoreEvents: [ScorePerformanceControllerEvent],
        observations: [PerformanceObservation],
        performanceStart: PerformanceMonotonicInstant,
        timeMap: ScorePerformancePlanTimeMap,
        reservedScores: Set<PerformanceAlignmentControllerScoreReference>
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
        let availableScoreEvents = scoreEvents.filter {
            reservedScores.contains(.init(event: $0)) == false
        }
        guard observations.contains(where: { $0.source.capabilities.controllers != .unavailable }) else {
            return availableScoreEvents.map { .notObserved(score: .init(event: $0)) }
        }

        let costs = observed.map { item in
            availableScoreEvents.enumerated().compactMap { index, scoreEvent
                -> (targetIndex: Int, cost: Double)? in
                guard item.1 == Int(scoreEvent.controllerNumber) else { return nil }
                let scoreSeconds = timeMap.seconds(at: scoreEvent.tick)
                let deviation = item.0.alignmentTimestamp.seconds
                    - performanceStart.seconds - scoreSeconds
                guard abs(deviation) <= configuration.candidateWindowSeconds else { return nil }
                let valueDeviation = abs(Double(item.2) - Double(scoreEvent.value)) / 127
                return (index, abs(deviation) + valueDeviation)
            }
        }
        let scoreByObservation = optimalTargetAssignments(
            costs: costs,
            targetCount: availableScoreEvents.count
        )
        let observationByScore = Dictionary(uniqueKeysWithValues: scoreByObservation.map {
            ($0.value, $0.key)
        })
        var links = availableScoreEvents.enumerated().map { scoreIndex, scoreEvent in
            guard let observationIndex = observationByScore[scoreIndex] else {
                return PerformanceAlignmentControllerLink.missing(score: .init(event: scoreEvent))
            }
            let item = observed[observationIndex]
            let scoreSeconds = timeMap.seconds(at: scoreEvent.tick)
            return .aligned(
                score: .init(event: scoreEvent),
                observation: .init(observation: item.0),
                timeDeviationSeconds: item.0.alignmentTimestamp.seconds
                    - performanceStart.seconds - scoreSeconds,
                normalizedValueDeviation: abs(Double(item.2) - Double(scoreEvent.value)) / 127
            )
        }
        links.append(contentsOf: observed.indices
            .filter { scoreByObservation[$0] == nil }
            .map { .extra(observation: .init(observation: observed[$0].0)) })
        return links
    }

    private func candidateSnapshot(
        for observation: PerformanceObservation,
        preparedPlan: PreparedPlan,
        performanceStart: PerformanceMonotonicInstant,
        generation: UInt64?,
        observedOnsetsByPitch: [Int: [ObservedOnset]],
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
            let chordOnsets = measuresChordSpread
                ? Dictionary(grouping: chordEvents, by: \.midiNote).flatMap { pitch, events in
                    observedOnsetsByPitch[pitch, default: []]
                        .filter {
                            abs($0.seconds - chordSeconds) <= configuration.candidateWindowSeconds
                        }
                        .sorted { lhs, rhs in
                            let lhsDistance = abs(lhs.seconds - chordSeconds)
                            let rhsDistance = abs(rhs.seconds - chordSeconds)
                            if lhsDistance != rhsDistance { return lhsDistance < rhsDistance }
                            return lhs.observationID.uuidString < rhs.observationID.uuidString
                        }
                        .prefix(events.count)
                        .map(\.seconds)
                }
                : []
            let hasCompleteChordMeasurement = measuresChordSpread
                && chordOnsets.count == chordEvents.count
            let chordSpread = hasCompleteChordMeasurement
                ? (chordOnsets.max().flatMap { maximum in
                    chordOnsets.min().map { maximum - $0 }
                }) ?? 0
                : 0
            let pitchCost = event.midiNote == observedNote ? 0 : configuration.pitchMismatchCost
            let onsetCost = onsetEvidence == .unavailable
                ? 0
                : abs(onsetDeviation) * configuration.onsetWeight
            let chordCost = hasCompleteChordMeasurement
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
                        status: hasCompleteChordMeasurement
                            ? Self.evidenceStatus(polyphonyEvidence)
                            : .notObserved,
                        cost: hasCompleteChordMeasurement ? chordCost : nil,
                        deviationSeconds: hasCompleteChordMeasurement ? chordSpread : nil
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

    func updatingReleaseEvidence(
        in link: PerformanceAlignmentLink,
        duration: TimeInterval,
        preparedPlan: PreparedPlan
    ) -> PerformanceAlignmentLink {
        guard case let .aligned(score, observation, evidence) = link,
              let event = preparedPlan.eventByID[score.eventID]
        else { return link }
        let releaseEvidence = Self.releaseEvidence(
            measurement: .init(duration: duration, capability: observation.source.capabilities.release),
            event: event,
            timeMap: preparedPlan.timeMap,
            onsetDeviation: evidence.first { $0.dimension == .onset }?.deviationSeconds,
            unmatchedCost: configuration.unmatchedCost
        )
        return .aligned(
            score: score,
            observation: observation,
            evidence: evidence.filter {
                $0.dimension != .release && $0.dimension != .duration
            } + releaseEvidence
        )
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
