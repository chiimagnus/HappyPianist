import Foundation

struct IncrementalPerformanceAligner: Sendable {
    private struct SourceIdentity: Hashable, Sendable {
        let kind: String
        let id: String
    }

    private struct NoteReleaseRoute: Hashable, Sendable {
        let source: PerformanceObservation.Source
        let channel: Int?
        let group: Int?
        let note: Int
    }

    private struct ContactReleaseRoute: Hashable, Sendable {
        let source: PerformanceObservation.Source
        let id: String
    }

    private struct OpenRelease: Sendable {
        let observationID: UUID
        let seconds: TimeInterval
    }

    enum State: Equatable, Sendable {
        case idle
        case running
        case finished
    }

    struct Configuration: Equatable, Sendable {
        let maximumBufferedObservations: Int
        let commitHorizonSeconds: TimeInterval

        init(maximumBufferedObservations: Int = 4_096, commitHorizonSeconds: TimeInterval = 0.3) {
            self.maximumBufferedObservations = max(32, maximumBufferedObservations)
            self.commitHorizonSeconds = commitHorizonSeconds.isFinite
                ? max(0, commitHorizonSeconds)
                : 0.3
        }
    }

    private let engine: PerformanceAlignmentEngine
    private let configuration: Configuration
    private(set) var state: State = .idle
    private(set) var appendSnapshot: PerformanceAlignment?
    private(set) var discardedObservationCount = 0
    private var plan: ScorePerformancePlan?
    private var preparedPlan: PerformanceAlignmentEngine.PreparedPlan?
    private var generation: UInt64?
    private var sourceGenerations: [SourceIdentity: UInt64] = [:]
    private var acceptedObservationIDs: Set<UUID> = []
    private var performanceStart = PerformanceMonotonicInstant(seconds: 0)
    private var observations: [PerformanceObservation] = []
    private var lastTimestamp: PerformanceMonotonicInstant?
    private var committedLinks: [UUID: PerformanceAlignmentLink] = [:]
    private var committedLinkOrder: [UUID] = []
    private var committedScoreEvents: Set<ScorePerformanceNoteEventID> = []
    private var committedControllerLinks: [UUID: PerformanceAlignmentControllerLink] = [:]
    private var committedControllerLinkOrder: [UUID] = []
    private var committedControllerScores: Set<PerformanceAlignmentControllerScoreReference> = []
    private var openNotes: [NoteReleaseRoute: [OpenRelease]] = [:]
    private var openContacts: [ContactReleaseRoute: OpenRelease] = [:]

    var bufferedObservationCount: Int { observations.count }

    init(
        engine: PerformanceAlignmentEngine = .init(),
        configuration: Configuration = .init()
    ) {
        self.engine = engine
        self.configuration = configuration
    }

    mutating func start(
        plan: ScorePerformancePlan,
        generation: UInt64?,
        performanceStart: PerformanceMonotonicInstant,
        activeTickRange: Range<Int>? = nil
    ) {
        reset()
        self.plan = plan
        preparedPlan = engine.prepare(plan: plan, activeTickRange: activeTickRange)
        self.generation = generation
        self.performanceStart = performanceStart
        state = .running
        appendSnapshot = nil
    }

    mutating func append(_ observation: PerformanceObservation) -> PerformanceAlignment? {
        guard accept(observation) else { return nil }
        let snapshot = liveSnapshot()
        commitMatureLinks(from: snapshot, now: observation.alignmentTimestamp)
        trimBuffer(using: snapshot)
        appendSnapshot = liveSnapshot()
        return appendSnapshot
    }

    mutating func appendReplayObservations(_ replayObservations: [PerformanceObservation]) {
        // ponytail: offline replay needs only the final alignment; online append owns transient snapshots.
        for observation in replayObservations {
            _ = accept(observation)
        }
    }

    mutating func finish() -> PerformanceAlignment? {
        guard state == .running, let preparedPlan else { return nil }
        let final = engine.align(
            preparedPlan: preparedPlan,
            observations: liveObservations(),
            performanceStart: performanceStart,
            generation: generation,
            reservedScoreEventIDs: committedScoreEvents,
            reservedControllerScores: committedControllerScores
        )
        state = .finished
        appendSnapshot = mergingCommitted(into: final, includeMissing: true)
        return appendSnapshot
    }

    mutating func reset() {
        state = .idle
        appendSnapshot = nil
        discardedObservationCount = 0
        plan = nil
        preparedPlan = nil
        generation = nil
        sourceGenerations.removeAll(keepingCapacity: true)
        acceptedObservationIDs.removeAll(keepingCapacity: true)
        performanceStart = .init(seconds: 0)
        clearRunEvidence()
    }

    private func liveSnapshot() -> PerformanceAlignment? {
        guard let preparedPlan else { return nil }
        let alignment = engine.align(
            preparedPlan: preparedPlan,
            observations: liveObservations(),
            performanceStart: performanceStart,
            generation: generation,
            includeMissing: false,
            reservedScoreEventIDs: committedScoreEvents,
            reservedControllerScores: committedControllerScores
        )
        return mergingCommitted(into: provisionalizing(alignment), includeMissing: false)
    }

    private func liveObservations() -> [PerformanceObservation] {
        observations.filter {
            committedLinks[$0.id] == nil && committedControllerLinks[$0.id] == nil
        }
    }

    private func provisionalizing(_ alignment: PerformanceAlignment) -> PerformanceAlignment {
        let now = lastTimestamp ?? performanceStart
        let links = alignment.links.map { link -> PerformanceAlignmentLink in
            guard case let .aligned(score, observation, evidence) = link,
                  isMature(observation: observation, now: now) == false
            else { return link }
            return .provisional(
                score: score,
                observation: observation,
                candidates: [.init(
                    score: score,
                    totalCost: evidence.compactMap(\.cost).reduce(0, +),
                    evidence: evidence
                )]
            )
        }
        return PerformanceAlignment(
            planID: alignment.planID,
            sourceGeneration: alignment.sourceGeneration,
            links: links,
            controllerLinks: alignment.controllerLinks
        )
    }

    private func mergingCommitted(
        into alignment: PerformanceAlignment,
        includeMissing: Bool
    ) -> PerformanceAlignment {
        let live = alignment.links.filter { link in
            if includeMissing == false, case .missing = link { return false }
            guard let observationID = link.observationID else { return true }
            return committedLinks[observationID] == nil
        }
        let liveControllers = alignment.controllerLinks.filter { link in
            guard let observationID = link.observationID else { return true }
            return committedControllerLinks[observationID] == nil
        }
        return PerformanceAlignment(
            planID: alignment.planID,
            sourceGeneration: alignment.sourceGeneration,
            links: committedLinkOrder.compactMap { committedLinks[$0] } + live,
            controllerLinks: committedControllerLinkOrder.compactMap {
                committedControllerLinks[$0]
            } + liveControllers
        )
    }

    private mutating func commitMatureLinks(
        from alignment: PerformanceAlignment?,
        now: PerformanceMonotonicInstant
    ) {
        guard let alignment else { return }
        for link in alignment.links {
            guard let observation = link.observationReference,
                  isMature(observation: observation, now: now)
            else { continue }
            commit(link)
        }
        for link in alignment.controllerLinks {
            guard let observation = link.observationReference,
                  isMature(observation: observation, now: now)
            else { continue }
            commit(link)
        }
    }

    private func isMature(
        observation: PerformanceAlignmentObservationReference,
        now: PerformanceMonotonicInstant
    ) -> Bool {
        // ponytail: an observation can compete with another one a score window later;
        // keep two windows, then use per-candidate deadlines if live latency is measured as a problem.
        let safeHorizon = max(
            configuration.commitHorizonSeconds,
            engine.candidateWindowSeconds * 2
        )
        return observation.correctedTime.seconds <= now.seconds - safeHorizon
    }

    private mutating func trimBuffer(using alignment: PerformanceAlignment?) {
        guard observations.count > configuration.maximumBufferedObservations else { return }
        let committedIDs = Set(committedLinks.keys).union(committedControllerLinks.keys)
        var evictedIDs = Set(observations.lazy.filter {
            committedIDs.contains($0.id) || $0.isDiscardableAlignmentAuxiliary
        }.map(\.id))
        let overflow = observations.count - evictedIDs.count - configuration.maximumBufferedObservations
        if overflow > 0 {
            let preferredEvictedIDs = evictedIDs
            evictedIDs.formUnion(observations.lazy.filter {
                preferredEvictedIDs.contains($0.id) == false
            }.prefix(overflow).map(\.id))
        }
        if let alignment {
            for link in alignment.links where link.observationID.map(evictedIDs.contains) == true {
                commitForced(link)
            }
            for link in alignment.controllerLinks where link.observationID.map(evictedIDs.contains) == true {
                commit(link)
            }
        }
        // ponytail: discard semantically inert controller traffic before freezing unresolved musical evidence.
        observations.removeAll { evictedIDs.contains($0.id) }
        discardedObservationCount += evictedIDs.count
    }

    private mutating func commitForced(_ link: PerformanceAlignmentLink) {
        guard case let .provisional(score, observation, candidates) = link else {
            commit(link)
            return
        }
        guard let candidate = candidates.first else { return }
        commit(.aligned(score: score, observation: observation, evidence: candidate.evidence))
    }

    private mutating func commit(_ link: PerformanceAlignmentLink) {
        guard let observationID = link.observationID else { return }
        if committedLinks[observationID] == nil {
            committedLinkOrder.append(observationID)
        }
        committedLinks[observationID] = link
        if case let .aligned(score, _, _) = link {
            committedScoreEvents.insert(score.eventID)
        }
    }

    private mutating func commit(_ link: PerformanceAlignmentControllerLink) {
        guard let observationID = link.observationID else { return }
        if committedControllerLinks[observationID] == nil {
            committedControllerLinkOrder.append(observationID)
        }
        committedControllerLinks[observationID] = link
        if case let .aligned(score, _, _, _) = link {
            committedControllerScores.insert(score)
        }
    }

    private mutating func clearRunEvidence() {
        observations.removeAll(keepingCapacity: true)
        lastTimestamp = nil
        committedLinks.removeAll(keepingCapacity: true)
        committedLinkOrder.removeAll(keepingCapacity: true)
        committedScoreEvents.removeAll(keepingCapacity: true)
        committedControllerLinks.removeAll(keepingCapacity: true)
        committedControllerLinkOrder.removeAll(keepingCapacity: true)
        committedControllerScores.removeAll(keepingCapacity: true)
        openNotes.removeAll(keepingCapacity: true)
        openContacts.removeAll(keepingCapacity: true)
    }

    private mutating func accept(_ observation: PerformanceObservation) -> Bool {
        guard state == .running,
              observation.source.role != .systemPlayback,
              observation.alignmentTimestamp >= performanceStart,
              acceptsGeneration(of: observation.source),
              lastTimestamp.map({ observation.alignmentTimestamp >= $0 }) ?? true,
              acceptedObservationIDs.insert(observation.id).inserted
        else {
            return false
        }
        observations.append(observation)
        trackRelease(for: observation)
        lastTimestamp = observation.alignmentTimestamp
        return true
    }

    private mutating func trackRelease(for observation: PerformanceObservation) {
        switch observation.event {
        case let .noteOn(note, _):
            let route = NoteReleaseRoute(
                source: observation.source,
                channel: observation.channel,
                group: observation.group,
                note: note
            )
            openNotes[route, default: []].append(.init(
                observationID: observation.id,
                seconds: observation.alignmentTimestamp.seconds
            ))
        case let .noteOff(note, _):
            let route = NoteReleaseRoute(
                source: observation.source,
                channel: observation.channel,
                group: observation.group,
                note: note
            )
            guard var notes = openNotes[route], notes.isEmpty == false else { return }
            let started = notes.removeFirst()
            openNotes[route] = notes
            completeRelease(started, at: observation.alignmentTimestamp.seconds)
        case let .contact(id, keyCandidate, .started) where keyCandidate != nil:
            openContacts[.init(source: observation.source, id: id)] = .init(
                observationID: observation.id,
                seconds: observation.alignmentTimestamp.seconds
            )
        case let .contact(id, _, .ended):
            guard let started = openContacts.removeValue(forKey: .init(
                source: observation.source,
                id: id
            )) else { return }
            completeRelease(started, at: observation.alignmentTimestamp.seconds)
        default:
            return
        }
    }

    private mutating func completeRelease(_ started: OpenRelease, at seconds: TimeInterval) {
        guard let link = committedLinks[started.observationID], let preparedPlan else { return }
        committedLinks[started.observationID] = engine.updatingReleaseEvidence(
            in: link,
            duration: max(0, seconds - started.seconds),
            preparedPlan: preparedPlan
        )
    }

    private mutating func acceptsGeneration(of source: PerformanceObservation.Source) -> Bool {
        if let generation {
            return source.generation == generation
        }
        let identity = SourceIdentity(kind: source.kind.rawValue, id: source.id)
        if let acceptedGeneration = sourceGenerations[identity] {
            return source.generation == acceptedGeneration
        }
        sourceGenerations[identity] = source.generation
        return true
    }
}

private extension PerformanceObservation {
    var isDiscardableAlignmentAuxiliary: Bool {
        guard case let .controller(controller) = event else { return false }
        guard source.capabilities.controllers != .unavailable else { return true }
        guard case let .controlChange(number, _) = controller,
              let controllerNumber = UInt8(exactly: number)
        else { return true }
        return MusicXMLPedalController(rawValue: controllerNumber) == nil
    }
}

private extension PerformanceAlignmentLink {
    var observationReference: PerformanceAlignmentObservationReference? {
        switch self {
        case let .aligned(_, observation, _),
             let .extra(observation, _, _),
             let .ambiguous(observation, _),
             let .provisional(_, observation, _),
             let .unknown(observation, _):
            observation
        case .missing:
            nil
        }
    }

    var observationID: UUID? { observationReference?.observationID }
}

private extension PerformanceAlignmentControllerLink {
    var observationReference: PerformanceAlignmentObservationReference? {
        switch self {
        case let .aligned(_, observation, _, _),
             let .extra(observation):
            observation
        case .missing, .notObserved:
            nil
        }
    }

    var observationID: UUID? { observationReference?.observationID }
}
