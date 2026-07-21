import Foundation

struct SongPracticeFocusMeasureBuilder {
    func build(from progress: SongPracticeProgress?) -> [SongPracticeFocusMeasure] {
        guard let progress else { return [] }
        let factsBySource = Dictionary(
            grouping: SongPracticeMeasureFactOrder.uniqueRealFacts(in: progress.measureFacts),
            by: \.sourceMeasureID
        )

        return factsBySource.compactMap { sourceMeasureID, facts in
            Self.candidate(sourceMeasureID: sourceMeasureID, facts: facts)
        }
        .sorted(by: Self.candidateComesFirst)
        .prefix(3)
        .map { candidate in
            SongPracticeFocusMeasure(
                sourceMeasureID: candidate.sourceMeasureID,
                reason: candidate.reason
            )
        }
    }

    private struct Candidate {
        let sourceMeasureID: PracticeSourceMeasureID
        let recentIssue: PracticeIssueKind?
        let failedAttempts: Int
        let lastAttemptAt: Date?

        var reason: SongPracticeFocusReason {
            if let recentIssue { return .recentIssue(recentIssue) }
            if failedAttempts > 0 { return .failedAttempts(failedAttempts) }
            return .learning
        }
    }

    private static func candidate(
        sourceMeasureID: PracticeSourceMeasureID,
        facts: [MeasurePracticeFacts]
    ) -> Candidate? {
        let stableHands = Set(facts.filter { $0.state == .pitchStepStable }.map(\.handMode))
        guard stableHands.contains(.both) == false,
              (stableHands.contains(.left) && stableHands.contains(.right)) == false
        else {
            return nil
        }
        let issueFact = facts
            .filter { $0.recentIssue != nil }
            .sorted(by: SongPracticeMeasureFactOrder.comesFirst)
            .first
        let failedAttempts = facts.reduce(into: 0) { total, fact in
            let (sum, overflow) = total.addingReportingOverflow(fact.failedAttempts)
            total = overflow ? .max : sum
        }
        return Candidate(
            sourceMeasureID: sourceMeasureID,
            recentIssue: issueFact?.recentIssue,
            failedAttempts: failedAttempts,
            lastAttemptAt: facts.compactMap(\.lastAttemptAt).max()
        )
    }

    private static func candidateComesFirst(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        if (lhs.recentIssue != nil) != (rhs.recentIssue != nil) {
            return lhs.recentIssue != nil
        }
        if lhs.failedAttempts != rhs.failedAttempts {
            return lhs.failedAttempts > rhs.failedAttempts
        }
        if lhs.lastAttemptAt != rhs.lastAttemptAt {
            return (lhs.lastAttemptAt ?? .distantPast) > (rhs.lastAttemptAt ?? .distantPast)
        }
        return PracticeSourceMeasureOrder.comesFirst(lhs.sourceMeasureID, rhs.sourceMeasureID)
    }
}

enum SongPracticeMeasureFactOrder {
    static func uniqueRealFacts(in facts: [MeasurePracticeFacts]) -> [MeasurePracticeFacts] {
        Dictionary(grouping: facts.filter(hasRealAttempt)) {
            MeasureHandIdentity(sourceMeasureID: $0.sourceMeasureID, handMode: $0.handMode)
        }.values.compactMap { $0.sorted(by: comesFirst).first }
    }

    static func hasRealAttempt(_ fact: MeasurePracticeFacts) -> Bool {
        fact.successfulAttempts > 0 || fact.failedAttempts > 0 || fact.lastAttemptAt != nil
    }

    static func comesFirst(_ lhs: MeasurePracticeFacts, _ rhs: MeasurePracticeFacts) -> Bool {
        if lhs.lastAttemptAt != rhs.lastAttemptAt {
            return (lhs.lastAttemptAt ?? .distantPast) > (rhs.lastAttemptAt ?? .distantPast)
        }
        if statePriority(lhs.state) != statePriority(rhs.state) {
            return statePriority(lhs.state) > statePriority(rhs.state)
        }
        if lhs.successfulAttempts != rhs.successfulAttempts {
            return lhs.successfulAttempts > rhs.successfulAttempts
        }
        if lhs.failedAttempts != rhs.failedAttempts {
            return lhs.failedAttempts > rhs.failedAttempts
        }
        if lhs.consecutiveSuccesses != rhs.consecutiveSuccesses {
            return lhs.consecutiveSuccesses > rhs.consecutiveSuccesses
        }
        if lhs.highestPitchStepStableTempoScale != rhs.highestPitchStepStableTempoScale {
            return (lhs.highestPitchStepStableTempoScale ?? 0) > (rhs.highestPitchStepStableTempoScale ?? 0)
        }
        return (lhs.recentIssue?.rawValue ?? "") > (rhs.recentIssue?.rawValue ?? "")
    }

    private static func statePriority(_ state: MeasurePitchStepLearningState) -> Int {
        switch state {
        case .notStarted: 0
        case .learning: 1
        case .pitchStepStable: 2
        }
    }
}

enum PracticeSourceMeasureOrder {
    static func comesFirst(
        _ lhs: PracticeSourceMeasureID,
        _ rhs: PracticeSourceMeasureID
    ) -> Bool {
        if lhs.partID != rhs.partID { return lhs.partID < rhs.partID }
        if lhs.sourceMeasureIndex != rhs.sourceMeasureIndex {
            return lhs.sourceMeasureIndex < rhs.sourceMeasureIndex
        }
        return switch (lhs.sourceNumberToken, rhs.sourceNumberToken) {
        case (nil, .some): true
        case (.some, nil): false
        case let (.some(lhsToken), .some(rhsToken)): lhsToken < rhsToken
        case (nil, nil): false
        }
    }
}

private struct MeasureHandIdentity: Hashable {
    let sourceMeasureID: PracticeSourceMeasureID
    let handMode: PracticeHandMode
}
