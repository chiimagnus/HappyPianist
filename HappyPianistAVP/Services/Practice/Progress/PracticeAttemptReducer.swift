import Foundation

enum PracticeSessionFact: Equatable {
    case attemptMatched(sourceMeasureID: PracticeSourceMeasureID, handMode: PracticeHandMode)
    case attemptIssue(sourceMeasureID: PracticeSourceMeasureID, issue: PracticeIssueKind)
    case passageCompleted(handMode: PracticeHandMode)
}

struct PracticeAttemptReductionState: Equatable {
    var failedStepIndices: Set<Int> = []
    var failedOccurrences: Set<PracticeMeasureOccurrenceID> = []
    var matchedStepIndicesByOccurrence: [PracticeMeasureOccurrenceID: Set<Int>] = [:]
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

        let issue: PracticeIssueKind?
        switch outcome {
        case .matched:
            issue = nil
        case .wrongNote:
            issue = .wrongNote
        case .missingNotes:
            issue = .missedNote
        case .incompleteChord:
            issue = .incompleteChord
        case .insufficientEvidence:
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
        facts.lastAttemptAt = timestamp

        let fact: PracticeSessionFact
        if let issue {
            facts.state = .learning
            if state.failedStepIndices.insert(stepIndex).inserted {
                facts.failedAttempts += 1
            }
            facts.consecutiveSuccesses = 0
            facts.recentIssue = issue
            state.failedOccurrences.insert(occurrenceID)
            fact = .attemptIssue(sourceMeasureID: sourceMeasureID, issue: issue)
        } else {
            state.failedStepIndices.remove(stepIndex)
            state.matchedStepIndicesByOccurrence[occurrenceID, default: []].insert(stepIndex)
            if facts.state == .notStarted {
                facts.state = .learning
            }
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
                    facts.recentIssue = nil
                    facts.successfulAttempts += 1
                    facts.consecutiveSuccesses += 1
                    if facts.consecutiveSuccesses >= configuration.requiredSuccesses {
                        facts.state = .pitchStepStable
                        facts.highestPitchStepStableTempoScale = max(
                            facts.highestPitchStepStableTempoScale ?? 0,
                            configuration.tempoScale
                        )
                    }
                }
                state.failedOccurrences.remove(occurrenceID)
                state.matchedStepIndicesByOccurrence.removeValue(forKey: occurrenceID)
            }
            fact = .attemptMatched(sourceMeasureID: sourceMeasureID, handMode: configuration.handMode)
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
        timestamp: Date
    ) -> Result {
        var updated = progress ?? emptyProgress(identity: identity, configuration: configuration, timestamp: timestamp)
        if let previousConfiguration = updated.activeConfiguration,
           previousConfiguration.handMode != configuration.handMode || previousConfiguration.tempoScale != configuration.tempoScale
        {
            for index in updated.measureFacts.indices where updated.measureFacts[index].handMode == configuration.handMode {
                updated.measureFacts[index].consecutiveSuccesses = 0
                updated.measureFacts[index].state = learningState(
                    for: updated.measureFacts[index],
                    tempoScale: configuration.tempoScale
                )
            }
        }
        updated.activeConfiguration = configuration
        updated.updatedAt = timestamp
        return Result(progress: updated, reductionState: .init(), fact: nil)
    }

    func reducePassageCompletion(
        progress: SongPracticeProgress?,
        reductionState: PracticeAttemptReductionState,
        identity: PracticeSongIdentity,
        configuration: PracticeRoundConfiguration,
        timestamp: Date,
        assessment: PassagePerformanceAssessment? = nil
    ) -> Result {
        var updated = progress ?? emptyProgress(identity: identity, configuration: configuration, timestamp: timestamp)
        updated.activeConfiguration = configuration
        updated.updatedAt = timestamp
        if let assessment {
            updated = reducePerformanceAssessment(
                progress: updated,
                identity: identity,
                configuration: configuration,
                timestamp: timestamp,
                assessment: assessment
            )
        }
        return Result(
            progress: updated,
            reductionState: reductionState,
            fact: .passageCompleted(handMode: configuration.handMode)
        )
    }

    func reducePerformanceAssessment(
        progress: SongPracticeProgress,
        identity: PracticeSongIdentity,
        configuration: PracticeRoundConfiguration,
        timestamp: Date,
        assessment: PassagePerformanceAssessment
    ) -> SongPracticeProgress {
        guard progress.identity == identity else { return progress }
        var updated = progress
        updated.activeConfiguration = configuration
        updated.updatedAt = max(progress.updatedAt, timestamp)
        reducePerformanceMaturity(
            assessment,
            handMode: configuration.handMode,
            timestamp: timestamp,
            into: &updated
        )
        return updated
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

    private func learningState(
        for facts: MeasurePracticeFacts,
        tempoScale: Double
    ) -> MeasurePitchStepLearningState {
        if let highestPitchStepStableTempoScale = facts.highestPitchStepStableTempoScale,
           highestPitchStepStableTempoScale >= tempoScale
        {
            return .pitchStepStable
        }
        return facts.successfulAttempts == 0 && facts.failedAttempts == 0 ? .notStarted : .learning
    }

    private func reducePerformanceMaturity(
        _ assessment: PassagePerformanceAssessment,
        handMode: PracticeHandMode,
        timestamp: Date,
        into progress: inout SongPracticeProgress
    ) {
        let grouped = Dictionary(grouping: assessment.measures) {
            $0.occurrenceID.sourceMeasureID
        }
        for (sourceMeasureID, assessments) in grouped {
            let dimensions = PerformanceAssessmentDimensionResult.aggregated(
                assessments.flatMap(\.dimensions)
            )
            guard dimensions.isEmpty == false else { continue }
            let coverage = PerformanceAssessmentEvidenceCoverage(dimensions: dimensions)
            let maturity: MeasurePerformanceMaturity
            if dimensions.allSatisfy({ $0.outcome == .correct }) {
                maturity = .mature
            } else if dimensions.contains(where: { $0.outcome == .incorrect }) {
                maturity = .developing
            } else {
                maturity = .insufficientEvidence
            }
            let summary = MeasurePerformanceMaturitySummary(
                maturity: maturity,
                rubricVersion: assessment.rubricVersion.rawValue,
                assessedDimensionCount: dimensions.count,
                sampleCount: dimensions.reduce(0) { $0 + $1.sampleCount },
                evidenceCoverage: coverage.ratio,
                metricSummaries: dimensions.map(MeasurePerformanceMetricSummary.init),
                assessedAt: timestamp
            )
            if let index = progress.measureFacts.firstIndex(where: {
                $0.sourceMeasureID == sourceMeasureID && $0.handMode == handMode
            }) {
                progress.measureFacts[index].performanceMaturity = summary
            } else {
                progress.measureFacts.append(MeasurePracticeFacts(
                    sourceMeasureID: sourceMeasureID,
                    handMode: handMode,
                    performanceMaturity: summary
                ))
            }
        }
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
