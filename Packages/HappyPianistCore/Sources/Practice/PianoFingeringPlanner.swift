import Foundation
import MusicXML

/// A bounded, deterministic dynamic-programming planner for one transport contact line.
public struct PianoFingeringPlanner: Sendable {
    public enum Source: String, Equatable, Sendable {
        case score
        case planned
    }

    public enum UnplannedReason: String, Equatable, Sendable {
        case missingTiming
        case missingKey
        case unknownHand
        case manualHandConflict
        case invalidManualFingering
        case ambiguousManualFingering
        case fingeringConflict
        case tooManySimultaneousNotes
        case spanExceeded
        case noSolution
        case budgetExceeded
    }

    public enum Resolution: Equatable, Sendable {
        case planned(hand: ScoreHand, finger: Int, source: Source)
        case unplanned(UnplannedReason)
    }

    public struct Result: Equatable, Identifiable, Sendable {
        public let occurrenceID: String
        public let resolution: Resolution

        public var id: String {
            occurrenceID
        }

        public init(occurrenceID: String, resolution: Resolution) {
            self.occurrenceID = occurrenceID
            self.resolution = resolution
        }
    }

    public struct Plan: Equatable, Sendable {
        public let results: [Result]

        public init(results: [Result]) {
            self.results = results.sorted { $0.occurrenceID < $1.occurrenceID }
        }

        public func result(forOccurrenceID occurrenceID: String) -> Result? {
            results.first { $0.occurrenceID == occurrenceID }
        }
    }

    public struct MotionLimits: Equatable, Sendable {
        public let maximumHandSpanMeters: Double
        public let maximumHandTravelMetersPerSecond: Double

        public init(
            maximumHandSpanMeters: Double = 0.20,
            maximumHandTravelMetersPerSecond: Double = 1.2
        ) {
            self.maximumHandSpanMeters = maximumHandSpanMeters.isFinite ? max(0, maximumHandSpanMeters) : 0
            self.maximumHandTravelMetersPerSecond = maximumHandTravelMetersPerSecond.isFinite
                ? max(0, maximumHandTravelMetersPerSecond)
                : 0
        }
    }

    // ponytail: bounded phrases keep candidate DP predictable; replace time splitting only when score phrase facts exist.
    private static let maximumContacts = 512
    private static let maximumGroupsPerPhrase = 48
    private static let phraseBreakSeconds: TimeInterval = 0.8
    private let motionLimits: MotionLimits

    public init(motionLimits: MotionLimits = MotionLimits()) {
        self.motionLimits = motionLimits
    }

    public func plan(
        contacts contactTimeline: PianoKeyContactTimeline,
        keyboardLayout: PianoFingeringKeyboardLayout
    ) throws -> Plan {
        try Task.checkCancellation()
        guard contactTimeline.contacts.count <= Self.maximumContacts else {
            return Plan(results: contactTimeline.contacts.map {
                Result(occurrenceID: $0.occurrenceID, resolution: .unplanned(.budgetExceeded))
            })
        }

        var resolutionByOccurrenceID: [String: Resolution] = [:]
        var resolvedContacts: [ResolvedContact] = []

        for contact in contactTimeline.contacts {
            try Task.checkCancellation()
            guard let onsetSeconds = contact.onsetSeconds, let releaseSeconds = contact.releaseSeconds else {
                resolutionByOccurrenceID[contact.occurrenceID] = .unplanned(.missingTiming)
                continue
            }
            guard let key = keyboardLayout.key(forMIDINote: contact.midiNote) else {
                resolutionByOccurrenceID[contact.occurrenceID] = .unplanned(.missingKey)
                continue
            }

            switch resolvedHand(for: contact) {
            case let .unplanned(reason):
                resolutionByOccurrenceID[contact.occurrenceID] = .unplanned(reason)
            case let .resolved(hand):
                switch manualFingering(for: contact, hand: hand) {
                case let .unplanned(reason):
                    resolutionByOccurrenceID[contact.occurrenceID] = .unplanned(reason)
                case let .finger(finger):
                    resolvedContacts.append(ResolvedContact(
                        contact: contact,
                        hand: hand,
                        key: key,
                        onsetSeconds: onsetSeconds,
                        releaseSeconds: releaseSeconds,
                        manualFinger: finger
                    ))
                }
            }
        }

        for hand in [ScoreHand.left, .right] {
            let contacts = resolvedContacts.filter { $0.hand == hand }
            try plan(
                contacts: contacts,
                hand: hand,
                into: &resolutionByOccurrenceID
            )
        }

        return Plan(results: contactTimeline.contacts.map { contact in
            Result(
                occurrenceID: contact.occurrenceID,
                resolution: resolutionByOccurrenceID[contact.occurrenceID] ?? .unplanned(.noSolution)
            )
        })
    }

    public func planOffMain(
        contacts: PianoKeyContactTimeline,
        keyboardLayout: PianoFingeringKeyboardLayout
    ) async throws -> Plan {
        try Task.checkCancellation()
        let task = Task.detached(priority: .userInitiated) { [self, contacts, keyboardLayout] in
            try plan(contacts: contacts, keyboardLayout: keyboardLayout)
        }
        return try await withTaskCancellationHandler(
            operation: { try await task.value },
            onCancel: { task.cancel() }
        )
    }

    private func plan(
        contacts: [ResolvedContact],
        hand: ScoreHand,
        into resolutionByOccurrenceID: inout [String: Resolution]
    ) throws {
        let groups = grouped(contacts)
        var pendingGroups: [CandidateGroup] = []

        func resolvePendingGroups() throws {
            guard pendingGroups.isEmpty == false else { return }
            try Task.checkCancellation()
            guard let shapes = bestShapes(for: pendingGroups, hand: hand) else {
                for group in pendingGroups {
                    for contact in group.candidates.first?.assignments ?? [] {
                        resolutionByOccurrenceID[contact.contact.contact.occurrenceID] = .unplanned(.noSolution)
                    }
                }
                pendingGroups.removeAll(keepingCapacity: true)
                return
            }
            for shape in shapes {
                for assignment in shape.assignments {
                    let source: Source = assignment.contact.manualFinger == nil ? .planned : .score
                    resolutionByOccurrenceID[assignment.contact.contact.occurrenceID] = .planned(
                        hand: hand,
                        finger: assignment.finger,
                        source: source
                    )
                }
            }
            pendingGroups.removeAll(keepingCapacity: true)
        }

        for group in groups {
            try Task.checkCancellation()
            switch candidateGroup(from: group, hand: hand) {
            case let .candidate(candidateGroup):
                if let previous = pendingGroups.last,
                   group.contacts.contains(where: { $0.contact.carriedIn }) ||
                    group.onsetSeconds - previous.onsetSeconds > Self.phraseBreakSeconds ||
                    pendingGroups.count == Self.maximumGroupsPerPhrase
                {
                    try resolvePendingGroups()
                }
                pendingGroups.append(candidateGroup)
            case let .unplanned(reason):
                try resolvePendingGroups()
                for contact in group.contacts {
                    resolutionByOccurrenceID[contact.contact.occurrenceID] = .unplanned(reason)
                }
            }
        }
        try resolvePendingGroups()
    }

    private func grouped(_ contacts: [ResolvedContact]) -> [ContactGroup] {
        let ordered = contacts.sorted {
            if $0.onsetSeconds != $1.onsetSeconds { return $0.onsetSeconds < $1.onsetSeconds }
            if $0.key.localX != $1.key.localX { return $0.key.localX < $1.key.localX }
            return $0.contact.occurrenceID < $1.contact.occurrenceID
        }
        var groups: [ContactGroup] = []
        for contact in ordered {
            if let index = groups.indices.last, groups[index].onsetSeconds == contact.onsetSeconds {
                groups[index].contacts.append(contact)
            } else {
                groups.append(ContactGroup(onsetSeconds: contact.onsetSeconds, contacts: [contact]))
            }
        }
        return groups
    }

    private func candidateGroup(
        from group: ContactGroup,
        hand: ScoreHand
    ) -> CandidateGroupResult {
        guard group.contacts.count <= 5 else { return .unplanned(.tooManySimultaneousNotes) }
        let sortedContacts = group.contacts.sorted {
            if $0.key.localX != $1.key.localX { return $0.key.localX < $1.key.localX }
            return $0.contact.occurrenceID < $1.contact.occurrenceID
        }
        guard Set(sortedContacts.map { $0.contact.midiNote }).count == sortedContacts.count else {
            return .unplanned(.fingeringConflict)
        }
        guard let minimumX = sortedContacts.first?.key.localX,
              let maximumX = sortedContacts.last?.key.localX,
              maximumX - minimumX <= motionLimits.maximumHandSpanMeters
        else {
            return .unplanned(.spanExceeded)
        }

        var partials = [FingerVector(fingers: [], usedFingers: [])]
        for contact in sortedContacts {
            let availableFingers = contact.manualFinger.map { [$0] } ?? Array(1 ... 5)
            var next: [FingerVector] = []
            for partial in partials {
                for finger in availableFingers where partial.usedFingers.contains(finger) == false {
                    next.append(FingerVector(
                        fingers: partial.fingers + [finger],
                        usedFingers: partial.usedFingers.union([finger])
                    ))
                }
            }
            partials = next
        }
        guard partials.isEmpty == false else { return .unplanned(.fingeringConflict) }

        let candidates = partials.map { vector in
            let assignments = zip(sortedContacts, vector.fingers).map {
                Assignment(contact: $0.0, finger: $0.1)
            }
            return Shape(
                assignments: assignments,
                onsetSeconds: group.onsetSeconds,
                releaseSeconds: assignments.map { $0.contact.releaseSeconds }.max() ?? group.onsetSeconds,
                anchorX: assignments.map { assignment in
                    assignment.contact.key.localX - fingerOffset(for: assignment.finger, hand: hand)
                }.reduce(0, +) / Double(assignments.count),
                staticCost: staticCost(assignments: assignments, hand: hand)
            )
        }
        return .candidate(CandidateGroup(onsetSeconds: group.onsetSeconds, candidates: candidates))
    }

    private func bestShapes(for phrase: [CandidateGroup], hand: ScoreHand) -> [Shape]? {
        guard let first = phrase.first else { return [] }
        var states = first.candidates.map { State(cost: $0.staticCost, previousIndex: nil) }
        var stateRows = [states]

        for groupIndex in phrase.indices.dropFirst() {
            let group = phrase[groupIndex]
            let previousGroup = phrase[groupIndex - 1]
            var nextStates: [State] = []
            for candidate in group.candidates {
                var bestState: State?
                for (previousIndex, previousState) in states.enumerated() {
                    guard let transitionCost = transitionCost(
                        from: previousGroup.candidates[previousIndex],
                        to: candidate,
                        hand: hand
                    ) else {
                        continue
                    }
                    let state = State(
                        cost: previousState.cost + candidate.staticCost + transitionCost,
                        previousIndex: previousIndex
                    )
                    if bestState == nil || state.cost < bestState!.cost {
                        bestState = state
                    }
                }
                guard let bestState else { return nil }
                nextStates.append(bestState)
            }
            states = nextStates
            stateRows.append(states)
        }

        guard let finalIndex = states.indices.min(by: { states[$0].cost < states[$1].cost }) else { return nil }
        var shapes = Array(repeating: first.candidates[0], count: phrase.count)
        var candidateIndex = finalIndex
        for groupIndex in phrase.indices.reversed() {
            shapes[groupIndex] = phrase[groupIndex].candidates[candidateIndex]
            guard groupIndex > phrase.startIndex else { break }
            guard let previousIndex = stateRows[groupIndex][candidateIndex].previousIndex else { return nil }
            candidateIndex = previousIndex
        }
        return shapes
    }

    private func staticCost(assignments: [Assignment], hand: ScoreHand) -> Double {
        assignments.enumerated().reduce(0) { cost, item in
            let preferredFinger = hand == .right ? item.offset + 1 : assignments.count - item.offset
            let orderCost = Double(abs(item.element.finger - preferredFinger)) * 0.04
            let blackThumbCost = item.element.contact.key.kind == .black && item.element.finger == 1 ? 0.12 : 0
            return cost + orderCost + blackThumbCost
        }
    }

    private func transitionCost(from previous: Shape, to current: Shape, hand: ScoreHand) -> Double? {
        let availableSeconds = max(0.01, current.onsetSeconds - previous.releaseSeconds)
        let travel = abs(current.anchorX - previous.anchorX)
        guard travel / availableSeconds <= motionLimits.maximumHandTravelMetersPerSecond else { return nil }
        var cost = travel / availableSeconds * 0.02

        for currentAssignment in current.assignments {
            guard let previousAssignment = previous.assignments.first(where: {
                $0.contact.contact.midiNote == currentAssignment.contact.contact.midiNote
            }) else {
                continue
            }
            cost += previousAssignment.finger == currentAssignment.finger ? -0.12 : 0.08
        }

        guard previous.assignments.count == 1, current.assignments.count == 1,
              let previousAssignment = previous.assignments.first,
              let currentAssignment = current.assignments.first
        else {
            return cost
        }
        let interval = currentAssignment.contact.contact.midiNote - previousAssignment.contact.contact.midiNote
        let previousFinger = orientedFinger(previousAssignment.finger, hand: hand)
        let currentFinger = orientedFinger(currentAssignment.finger, hand: hand)
        cost += Double(abs(currentFinger - previousFinger)) * 0.015
        if interval > 0 {
            if currentFinger == previousFinger + 1 {
                cost -= 0.16
            } else if previousFinger >= 3 && currentFinger == 1 {
                cost -= 0.18
            } else if currentFinger <= previousFinger {
                cost += 0.08
            } else {
                cost += Double(currentFinger - previousFinger - 1) * 0.04
            }
        } else if interval < 0 {
            if currentFinger == previousFinger - 1 {
                cost -= 0.16
            } else if previousFinger <= 3 && currentFinger == 5 {
                cost -= 0.18
            } else if currentFinger >= previousFinger {
                cost += 0.08
            } else {
                cost += Double(previousFinger - currentFinger - 1) * 0.04
            }
        }
        return cost
    }

    private func fingerOffset(for finger: Int, hand: ScoreHand) -> Double {
        let offset = Double(finger - 3) * 0.02
        return hand == .right ? offset : -offset
    }

    private func orientedFinger(_ finger: Int, hand: ScoreHand) -> Int {
        hand == .right ? finger : 6 - finger
    }

    private func resolvedHand(for contact: PianoKeyContactTimeline.Contact) -> HandResolution {
        let manualHands = contact.fingerings.compactMap { fingering -> ScoreHand? in
            switch fingering.hand {
            case .left: return .left
            case .right: return .right
            case .unspecified, .unsupported: return nil
            }
        }
        let distinctManualHands = manualHands.reduce(into: [ScoreHand]()) { result, hand in
            if result.contains(hand) == false { result.append(hand) }
        }

        switch contact.hand {
        case .left, .right:
            guard distinctManualHands.allSatisfy({ $0 == contact.hand }) else {
                return .unplanned(.manualHandConflict)
            }
            return .resolved(contact.hand)
        case .unknown:
            if distinctManualHands.count == 1, let hand = distinctManualHands.first {
                return .resolved(hand)
            }
            if distinctManualHands.count > 1 {
                return .unplanned(.manualHandConflict)
            }
            switch contact.staff {
            case 1: return .resolved(.right)
            case 2: return .resolved(.left)
            default: return .unplanned(.unknownHand)
            }
        }
    }

    private func manualFingering(
        for contact: PianoKeyContactTimeline.Contact,
        hand: ScoreHand
    ) -> ManualFingering {
        guard contact.fingerings.isEmpty == false else { return .finger(nil) }
        var values: [Int] = []
        for fingering in contact.fingerings {
            switch fingering.hand {
            case .left where hand != .left, .right where hand != .right:
                return .unplanned(.manualHandConflict)
            case .unsupported:
                return .unplanned(.invalidManualFingering)
            case .left, .right, .unspecified:
                guard let value = Int(fingering.text), (1 ... 5).contains(value) else {
                    return .unplanned(.invalidManualFingering)
                }
                values.append(value)
            }
        }
        let distinctValues = values.reduce(into: [Int]()) { result, value in
            if result.contains(value) == false { result.append(value) }
        }
        guard distinctValues.count == 1, let value = distinctValues.first else {
            return .unplanned(.ambiguousManualFingering)
        }
        return .finger(value)
    }
}

private extension PianoFingeringPlanner {
    struct ResolvedContact: Sendable {
        let contact: PianoKeyContactTimeline.Contact
        let hand: ScoreHand
        let key: PianoFingeringKeyboardLayout.Key
        let onsetSeconds: TimeInterval
        let releaseSeconds: TimeInterval
        let manualFinger: Int?
    }

    struct ContactGroup: Sendable {
        let onsetSeconds: TimeInterval
        var contacts: [ResolvedContact]
    }

    struct CandidateGroup: Sendable {
        let onsetSeconds: TimeInterval
        let candidates: [Shape]
    }

    struct FingerVector {
        let fingers: [Int]
        let usedFingers: Set<Int>
    }

    struct Assignment: Sendable {
        let contact: ResolvedContact
        let finger: Int

        init(contact: ResolvedContact, finger: Int) {
            self.contact = contact
            self.finger = finger
        }
    }

    struct Shape: Sendable {
        let assignments: [Assignment]
        let onsetSeconds: TimeInterval
        let releaseSeconds: TimeInterval
        let anchorX: Double
        let staticCost: Double
    }

    struct State {
        let cost: Double
        let previousIndex: Int?
    }

    enum HandResolution {
        case resolved(ScoreHand)
        case unplanned(UnplannedReason)
    }

    enum ManualFingering {
        case finger(Int?)
        case unplanned(UnplannedReason)
    }

    enum CandidateGroupResult {
        case candidate(CandidateGroup)
        case unplanned(UnplannedReason)
    }
}
