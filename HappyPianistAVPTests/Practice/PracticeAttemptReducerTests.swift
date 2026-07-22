import Foundation
@testable import HappyPianistAVP
import Testing

@Suite("Practice attempt reducer")
struct PracticeAttemptReducerTests {
    @Test func pitchStepStabilityRequiresConfiguredConsecutiveSuccessfulMeasurePasses() throws {
        let fixture = try Fixture(requiredSuccesses: 2)
        let reducer = PracticeAttemptReducer()
        var progress: SongPracticeProgress?
        var state = PracticeAttemptReductionState()

        for secondPass in [false, true] {
            let first = reducer.reduceAttempt(
                progress: progress,
                reductionState: state,
                outcome: fixture.matched(stepIndex: 0),
                stepIndex: 0,
                identity: fixture.identity,
                configuration: fixture.configuration,
                measureIndex: fixture.measureIndex,
                timestamp: secondPass ? Date(timeIntervalSince1970: 2) : Date(timeIntervalSince1970: 1)
            )
            progress = first.progress
            state = first.reductionState

            let last = reducer.reduceAttempt(
                progress: progress,
                reductionState: state,
                outcome: fixture.matched(stepIndex: 1),
                stepIndex: 1,
                identity: fixture.identity,
                configuration: fixture.configuration,
                measureIndex: fixture.measureIndex,
                timestamp: secondPass ? Date(timeIntervalSince1970: 4) : Date(timeIntervalSince1970: 3)
            )
            progress = last.progress
            state = last.reductionState
        }

        let facts = try #require(progress?.measureFacts.first)
        #expect(facts.successfulAttempts == 2)
        #expect(facts.consecutiveSuccesses == 2)
        #expect(facts.state == .pitchStepStable)
        #expect(facts.highestPitchStepStableTempoScale == 0.6)
        #expect(facts.performanceMaturity == nil)
    }

    @Test func failureResetsStreakAndDoesNotEraseHistoricalSuccess() throws {
        let fixture = try Fixture(requiredSuccesses: 2)
        let reducer = PracticeAttemptReducer()
        let firstStep = reducer.reduceAttempt(
            progress: nil,
            reductionState: .init(),
            outcome: fixture.matched(stepIndex: 0),
            stepIndex: 0,
            identity: fixture.identity,
            configuration: fixture.configuration,
            measureIndex: fixture.measureIndex,
            timestamp: .now
        )
        let success = reducer.reduceAttempt(
            progress: firstStep.progress,
            reductionState: firstStep.reductionState,
            outcome: fixture.matched(stepIndex: 1),
            stepIndex: 1,
            identity: fixture.identity,
            configuration: fixture.configuration,
            measureIndex: fixture.measureIndex,
            timestamp: .now
        )
        let failure = reducer.reduceAttempt(
            progress: success.progress,
            reductionState: success.reductionState,
            outcome: fixture.wrong(stepIndex: 0),
            stepIndex: 0,
            identity: fixture.identity,
            configuration: fixture.configuration,
            measureIndex: fixture.measureIndex,
            timestamp: .now
        )
        let repeatedFailure = reducer.reduceAttempt(
            progress: failure.progress,
            reductionState: failure.reductionState,
            outcome: fixture.wrong(stepIndex: 0),
            stepIndex: 0,
            identity: fixture.identity,
            configuration: fixture.configuration,
            measureIndex: fixture.measureIndex,
            timestamp: .now
        )

        let facts = try #require(repeatedFailure.progress.measureFacts.first)
        #expect(facts.successfulAttempts == 1)
        #expect(facts.failedAttempts == 1)
        #expect(facts.consecutiveSuccesses == 0)
        #expect(facts.recentIssue == .wrongNote)
    }

    @Test func failedOccurrenceKeepsIssueUntilANewCleanPass() throws {
        let fixture = try Fixture(requiredSuccesses: 2)
        let reducer = PracticeAttemptReducer()
        var progress: SongPracticeProgress?
        var state = PracticeAttemptReductionState()

        for (stepIndex, outcome) in [
            (0, fixture.wrong(stepIndex: 0)),
            (0, fixture.matched(stepIndex: 0)),
            (1, fixture.matched(stepIndex: 1)),
        ] {
            let result = reducer.reduceAttempt(
                progress: progress,
                reductionState: state,
                outcome: outcome,
                stepIndex: stepIndex,
                identity: fixture.identity,
                configuration: fixture.configuration,
                measureIndex: fixture.measureIndex,
                timestamp: .now
            )
            progress = result.progress
            state = result.reductionState
        }

        #expect(progress?.measureFacts.first?.successfulAttempts == 0)
        #expect(progress?.measureFacts.first?.recentIssue == .wrongNote)

        for stepIndex in 0 ... 1 {
            let result = reducer.reduceAttempt(
                progress: progress,
                reductionState: state,
                outcome: fixture.matched(stepIndex: stepIndex),
                stepIndex: stepIndex,
                identity: fixture.identity,
                configuration: fixture.configuration,
                measureIndex: fixture.measureIndex,
                timestamp: .now
            )
            progress = result.progress
            state = result.reductionState
        }
        #expect(progress?.measureFacts.first?.recentIssue == nil)
    }

    @Test func partialMatchDoesNotDowngradePitchStepStableMeasure() throws {
        let fixture = try Fixture(requiredSuccesses: 2)
        let reducer = PracticeAttemptReducer()
        let stable = MeasurePracticeFacts(
            sourceMeasureID: fixture.configuration.passage.start.sourceMeasureID,
            handMode: .right,
            state: .pitchStepStable,
            consecutiveSuccesses: 2,
            highestPitchStepStableTempoScale: 0.6
        )
        let progress = SongPracticeProgress(
            identity: fixture.identity,
            activeConfiguration: fixture.configuration,
            measureFacts: [stable],
            updatedAt: .now
        )
        let partial = reducer.reduceAttempt(
            progress: progress,
            reductionState: .init(),
            outcome: fixture.matched(stepIndex: 0),
            stepIndex: 0,
            identity: fixture.identity,
            configuration: fixture.configuration,
            measureIndex: fixture.measureIndex,
            timestamp: .now
        )
        #expect(partial.progress.measureFacts.first?.state == .pitchStepStable)

        let failed = reducer.reduceAttempt(
            progress: partial.progress,
            reductionState: partial.reductionState,
            outcome: fixture.wrong(stepIndex: 1),
            stepIndex: 1,
            identity: fixture.identity,
            configuration: fixture.configuration,
            measureIndex: fixture.measureIndex,
            timestamp: .now
        )
        #expect(failed.progress.measureFacts.first?.state == .learning)
    }

    @Test func insufficientEvidenceDoesNotCreateDurableFacts() throws {
        let fixture = try Fixture(requiredSuccesses: 3)
        let reducer = PracticeAttemptReducer()
        let result = reducer.reduceAttempt(
            progress: nil,
            reductionState: .init(),
            outcome: fixture.insufficient(stepIndex: 0),
            stepIndex: 0,
            identity: fixture.identity,
            configuration: fixture.configuration,
            measureIndex: fixture.measureIndex,
            timestamp: .now
        )

        #expect(result.progress.measureFacts.isEmpty)
        #expect(result.progress.resumePoint == nil)
        #expect(result.fact == nil)
    }

    @Test func tempoChangeStartsANewPitchStepStabilityStreak() throws {
        let fixture = try Fixture(requiredSuccesses: 2)
        let reducer = PracticeAttemptReducer()
        var progress: SongPracticeProgress?
        var state = PracticeAttemptReductionState()

        for stepIndex in 0 ... 1 {
            let result = reducer.reduceAttempt(
                progress: progress,
                reductionState: state,
                outcome: fixture.matched(stepIndex: stepIndex),
                stepIndex: stepIndex,
                identity: fixture.identity,
                configuration: fixture.configuration,
                measureIndex: fixture.measureIndex,
                timestamp: .now
            )
            progress = result.progress
            state = result.reductionState
        }

        let fasterConfiguration = fixture.configuration(tempoScale: 1)
        let restarted = reducer.reducePassageRestart(
            progress: progress,
            identity: fixture.identity,
            configuration: fasterConfiguration,
            timestamp: .now
        )
        progress = restarted.progress
        state = restarted.reductionState
        for stepIndex in 0 ... 1 {
            let result = reducer.reduceAttempt(
                progress: progress,
                reductionState: state,
                outcome: fixture.matched(stepIndex: stepIndex),
                stepIndex: stepIndex,
                identity: fixture.identity,
                configuration: fasterConfiguration,
                measureIndex: fixture.measureIndex,
                timestamp: .now
            )
            progress = result.progress
            state = result.reductionState
        }

        let facts = try #require(progress?.measureFacts.first)
        #expect(facts.successfulAttempts == 2)
        #expect(facts.consecutiveSuccesses == 1)
        #expect(facts.state == .learning)
    }

    @Test func passageAssessmentUpdatesMaturityWithoutChangingPitchStepState() throws {
        let fixture = try Fixture(requiredSuccesses: 2)
        let sourceMeasureID = fixture.configuration.passage.start.sourceMeasureID
        let progress = SongPracticeProgress(
            identity: fixture.identity,
            activeConfiguration: fixture.configuration,
            measureFacts: [MeasurePracticeFacts(
                sourceMeasureID: sourceMeasureID,
                handMode: .right,
                state: .pitchStepStable,
                consecutiveSuccesses: 2,
                highestPitchStepStableTempoScale: 0.6
            )],
            updatedAt: .now
        )
        let pitch = PerformanceAssessmentDimensionResult(
            dimension: .exactPitch,
            outcome: .correct,
            evidenceStatus: .observed,
            measurement: PerformanceAssessmentMeasurement(value: 1, unit: .ratio),
            sampleCount: 2,
            evidence: []
        )
        let assessment = PassagePerformanceAssessment(
            planID: .init(rawValue: "assessment-plan"),
            sourceGeneration: 1,
            tickRange: 0 ..< 960,
            rubricVersion: .capabilityAware,
            dimensions: [pitch],
            measures: [.init(
                occurrenceID: fixture.configuration.passage.start,
                tickRange: 0 ..< 960,
                dimensions: [pitch]
            )]
        )
        let timestamp = Date(timeIntervalSince1970: 100)

        let result = PracticeAttemptReducer().reducePassageCompletion(
            progress: progress,
            reductionState: .init(),
            identity: fixture.identity,
            configuration: fixture.configuration,
            timestamp: timestamp,
            assessment: assessment
        )
        let facts = try #require(result.progress.measureFacts.first)

        #expect(facts.state == .pitchStepStable)
        #expect(facts.performanceMaturity?.maturity == .mature)
        #expect(facts.performanceMaturity?.rubricVersion == "performance-assessment-v2")
        #expect(facts.performanceMaturity?.assessedDimensionCount == 1)
        #expect(facts.performanceMaturity?.sampleCount == 2)
        #expect(facts.performanceMaturity?.evidenceCoverage == 1)
        #expect(facts.performanceMaturity?.assessedAt == timestamp)
    }

    @Test func repeatedMeasureOccurrencesProduceOneConservativeMetricSummary() throws {
        let fixture = try Fixture(requiredSuccesses: 2)
        let sourceMeasureID = fixture.configuration.passage.start.sourceMeasureID
        let correct = PerformanceAssessmentDimensionResult(
            dimension: .exactPitch,
            outcome: .correct,
            evidenceStatus: .observed,
            measurement: PerformanceAssessmentMeasurement(value: 0.5, unit: .ratio),
            sampleCount: 2,
            confidence: 0.8,
            evidence: []
        )
        let incorrect = PerformanceAssessmentDimensionResult(
            dimension: .exactPitch,
            outcome: .incorrect,
            evidenceStatus: .degraded,
            measurement: PerformanceAssessmentMeasurement(value: 0.75, unit: .ratio),
            sampleCount: 6,
            confidence: 0.4,
            evidence: []
        )
        let assessment = PassagePerformanceAssessment(
            planID: .init(rawValue: "assessment-plan"),
            sourceGeneration: 1,
            tickRange: 0 ..< 1920,
            rubricVersion: .capabilityAware,
            dimensions: [incorrect],
            measures: [
                .init(
                    occurrenceID: .init(sourceMeasureID: sourceMeasureID, occurrenceIndex: 0),
                    tickRange: 0 ..< 960,
                    dimensions: [correct]
                ),
                .init(
                    occurrenceID: .init(sourceMeasureID: sourceMeasureID, occurrenceIndex: 1),
                    tickRange: 960 ..< 1920,
                    dimensions: [incorrect]
                ),
            ]
        )
        let progress = SongPracticeProgress(identity: fixture.identity, updatedAt: .distantPast)

        let reduced = PracticeAttemptReducer().reducePerformanceAssessment(
            progress: progress,
            identity: fixture.identity,
            configuration: fixture.configuration,
            timestamp: .now,
            assessment: assessment
        )
        let maturity = try #require(reduced.measureFacts.first?.performanceMaturity)
        let metric = try #require(maturity.metricSummaries.first)

        #expect(maturity.maturity == .developing)
        #expect(maturity.assessedDimensionCount == 1)
        #expect(maturity.sampleCount == 8)
        #expect(maturity.metricSummaries.count == 1)
        #expect(metric.dimension == .exactPitch)
        #expect(metric.outcome == .incorrect)
        #expect(metric.evidenceStatus == .degraded)
        #expect(metric.measurement?.value == 0.6875)
        #expect(metric.confidence == 0.5)
    }

    @Test func legacyStableTokenDecodesOnlyAsPitchStepStability() throws {
        let state = try JSONDecoder().decode(
            MeasurePitchStepLearningState.self,
            from: Data("\"stable\"".utf8)
        )

        #expect(state == .pitchStepStable)
    }
}

private struct Fixture {
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "fixture")
    let configuration: PracticeRoundConfiguration
    let measureIndex: PracticeMeasureIndex

    init(requiredSuccesses: Int) throws {
        let span = MusicXMLMeasureSpan(
            partID: "P1",
            measureNumber: 1,
            sourceMeasureIndex: 0,
            sourceMeasureNumberToken: "1",
            occurrenceIndex: 0,
            startTick: 0,
            endTick: 960
        )
        let passage = try #require(PracticePassage(start: span.occurrenceID, end: span.occurrenceID))
        configuration = PracticeRoundConfiguration(
            passage: passage,
            handMode: .right,
            tempoScale: 0.6,
            loopEnabled: true,
            requiredSuccesses: requiredSuccesses
        )
        measureIndex = PracticeMeasureIndex(
            steps: [
                PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1, handAssignment: .unknown)]),
                PracticeStep(tick: 480, notes: [PracticeStepNote(midiNote: 62, staff: 1, handAssignment: .unknown)]),
            ],
            measureSpans: [span]
        )
    }

    func matched(stepIndex _: Int) -> StepAttemptMatchResult {
        .matched
    }

    func wrong(stepIndex _: Int) -> StepAttemptMatchResult {
        .wrongNote
    }

    func insufficient(stepIndex _: Int) -> StepAttemptMatchResult {
        .insufficientEvidence
    }

    func configuration(tempoScale: Double) -> PracticeRoundConfiguration {
        PracticeRoundConfiguration(
            passage: configuration.passage,
            handMode: configuration.handMode,
            tempoScale: tempoScale,
            loopEnabled: configuration.loopEnabled,
            requiredSuccesses: configuration.requiredSuccesses
        )
    }
}
