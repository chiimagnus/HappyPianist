import Foundation

enum PracticeSessionFact: Equatable, Sendable {
    case attemptMatched(PracticeAttemptFact)
    case attemptIssue(PracticeAttemptFact, issue: PracticeIssueKind)
    case passageRestarted(PracticeRoundFact)
    case passageCompleted(PracticeRoundFact)
}

struct PracticeAttemptFact: Equatable, Sendable {
    let identity: PracticeSongIdentity
    let roundGeneration: Int
    let occurrenceID: PracticeMeasureOccurrenceID
    let stepIndex: Int
    let handMode: PracticeHandMode
    let tempoScale: Double
    let timestamp: Date
}

struct PracticeRoundFact: Equatable, Sendable {
    let identity: PracticeSongIdentity
    let roundGeneration: Int
    let passage: PracticePassage
    let handMode: PracticeHandMode
    let tempoScale: Double
    let timestamp: Date
}

struct PracticeAttemptReductionState: Equatable {
    var failedStepIndices: Set<Int> = []
    var failedOccurrences: Set<PracticeMeasureOccurrenceID> = []
    var matchedStepIndicesByOccurrence: [PracticeMeasureOccurrenceID: Set<Int>] = [:]

    mutating func resetPassageAttempt() {
        failedStepIndices.removeAll()
        failedOccurrences.removeAll()
        matchedStepIndicesByOccurrence.removeAll()
    }
}

struct PracticeAttemptReducer {
    struct Result: Equatable {
        let progress: SongPracticeProgress
        let reductionState: PracticeAttemptReductionState
        let fact: PracticeSessionFact?
    }

    func reduceAttempt(
        progress: SongPracticeProgress?,
        reductionState: PracticeAttemptReductionState,
        outcome: StepAttemptMatchResult,
        stepIndex: Int,
        identity: PracticeSongIdentity,
        configuration: PracticeRoundConfiguration,
        roundGeneration: Int,
        measureIndex: PracticeMeasureIndex,
        timestamp: Date
    ) -> Result {
        guard let occurrenceID = measureIndex.occurrenceID(forStepIndex: stepIndex) else {
            return Result(
                progress: progress ?? emptyProgress(identity: identity, configuration: configuration, timestamp: timestamp),
                reductionState: reductionState,
                fact: nil
            )
        }

        var state = reductionState
        var updated = progress ?? emptyProgress(identity: identity, configuration: configuration, timestamp: timestamp)
        updated.activeConfiguration = configuration
        updated.resumePoint = PracticeResumePoint(
            occurrenceID: occurrenceID,
            stepIndex: stepIndex,
            updatedAt: timestamp
        )
        updated.updatedAt = timestamp

        let sourceMeasureID = occurrenceID.sourceMeasureID
        let factsIndex = updated.measureFacts.firstIndex {
            $0.sourceMeasureID == sourceMeasureID && $0.handMode == configuration.handMode
        }
        var facts = factsIndex.map { updated.measureFacts[$0] } ?? MeasurePracticeFacts(
            sourceMeasureID: sourceMeasureID,
            handMode: configuration.handMode
        )
        facts.state = .learning
        facts.lastAttemptAt = timestamp

        let baseFact = PracticeAttemptFact(
            identity: identity,
            roundGeneration: roundGeneration,
            occurrenceID: occurrenceID,
            stepIndex: stepIndex,
            handMode: configuration.handMode,
            tempoScale: configuration.tempoScale,
            timestamp: timestamp
        )

        let fact: PracticeSessionFact?
        switch outcome.category {
        case .insufficientEvidence:
            fact = nil

        case .wrongNote, .missingNotes, .incompleteChord:
            let issue = outcome.issueKind ?? .missedNote
            if state.failedStepIndices.insert(stepIndex).inserted {
                facts.failedAttempts += 1
            }
            facts.consecutiveSuccesses = 0
            facts.recentIssue = issue
            state.failedOccurrences.insert(occurrenceID)
            fact = .attemptIssue(baseFact, issue: issue)

        case .matched:
            state.failedStepIndices.remove(stepIndex)
            state.matchedStepIndicesByOccurrence[occurrenceID, default: []].insert(stepIndex)
            facts.recentIssue = nil
            if let occurrenceStepRange = stepRange(
                for: occurrenceID,
                measureIndex: measureIndex,
                configuration: configuration
            ),
                stepIndex == occurrenceStepRange.upperBound - 1
            {
                let matchedIndices = state.matchedStepIndicesByOccurrence[occurrenceID, default: []]
                let completedEveryStep = occurrenceStepRange.allSatisfy { matchedIndices.contains($0) }
                if completedEveryStep, state.failedOccurrences.contains(occurrenceID) == false {
                    facts.successfulAttempts += 1
                    facts.consecutiveSuccesses += 1
                    if facts.consecutiveSuccesses >= configuration.requiredSuccesses {
                        facts.state = .stable
                        facts.highestStableTempoScale = max(
                            facts.highestStableTempoScale ?? 0,
                            configuration.tempoScale
                        )
                    }
                }
                state.failedOccurrences.remove(occurrenceID)
                state.matchedStepIndicesByOccurrence.removeValue(forKey: occurrenceID)
            }
            fact = .attemptMatched(baseFact)
        }

        if let factsIndex {
            updated.measureFacts[factsIndex] = facts
        } else {
            updated.measureFacts.append(facts)
        }

        return Result(progress: updated, reductionState: state, fact: fact)
    }

    func reducePassageRestart(
        progress: SongPracticeProgress?,
        identity: PracticeSongIdentity,
        configuration: PracticeRoundConfiguration,
        roundGeneration: Int,
        timestamp: Date
    ) -> Result {
        var updated = progress ?? emptyProgress(identity: identity, configuration: configuration, timestamp: timestamp)
        updated.activeConfiguration = configuration
        updated.updatedAt = timestamp
        let fact = PracticeSessionFact.passageRestarted(
            PracticeRoundFact(
                identity: identity,
                roundGeneration: roundGeneration,
                passage: configuration.passage,
                handMode: configuration.handMode,
                tempoScale: configuration.tempoScale,
                timestamp: timestamp
            )
        )
        return Result(progress: updated, reductionState: .init(), fact: fact)
    }

    func reducePassageCompletion(
        progress: SongPracticeProgress?,
        reductionState: PracticeAttemptReductionState,
        identity: PracticeSongIdentity,
        configuration: PracticeRoundConfiguration,
        roundGeneration: Int,
        timestamp: Date
    ) -> Result {
        var updated = progress ?? emptyProgress(identity: identity, configuration: configuration, timestamp: timestamp)
        updated.activeConfiguration = configuration
        updated.updatedAt = timestamp
        let fact = PracticeSessionFact.passageCompleted(
            PracticeRoundFact(
                identity: identity,
                roundGeneration: roundGeneration,
                passage: configuration.passage,
                handMode: configuration.handMode,
                tempoScale: configuration.tempoScale,
                timestamp: timestamp
            )
        )
        return Result(progress: updated, reductionState: reductionState, fact: fact)
    }

    private func emptyProgress(
        identity: PracticeSongIdentity,
        configuration: PracticeRoundConfiguration,
        timestamp: Date
    ) -> SongPracticeProgress {
        SongPracticeProgress(
            identity: identity,
            activeConfiguration: configuration,
            updatedAt: timestamp
        )
    }

    private func stepRange(
        for occurrenceID: PracticeMeasureOccurrenceID,
        measureIndex: PracticeMeasureIndex,
        configuration: PracticeRoundConfiguration
    ) -> Range<Int>? {
        guard configuration.passage.start.occurrenceIndex <= occurrenceID.occurrenceIndex,
              occurrenceID.occurrenceIndex <= configuration.passage.end.occurrenceIndex,
              let occurrencePosition = measureIndex.measureSpans.firstIndex(where: { $0.occurrenceID == occurrenceID })
        else {
            return nil
        }
        return try? measureIndex.stepRange(forOccurrenceRange: occurrencePosition ..< (occurrencePosition + 1))
    }
}
