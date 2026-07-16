import Foundation
@testable import HappyPianistAVP
import Testing

@Suite("Practice attempt reducer")
struct PracticeAttemptReducerTests {
    @Test func stableRequiresConfiguredConsecutiveSuccessfulMeasurePasses() throws {
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
        #expect(facts.state == .stable)
        #expect(facts.highestStableTempoScale == 0.6)
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

    @Test func partialMatchDoesNotDowngradeStableMeasure() throws {
        let fixture = try Fixture(requiredSuccesses: 2)
        let reducer = PracticeAttemptReducer()
        let stable = MeasurePracticeFacts(
            sourceMeasureID: fixture.configuration.passage.start.sourceMeasureID,
            handMode: .right,
            state: .stable,
            consecutiveSuccesses: 2,
            highestStableTempoScale: 0.6
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
        #expect(partial.progress.measureFacts.first?.state == .stable)

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

    @Test func tempoChangeStartsANewStableStreak() throws {
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
                PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1)]),
                PracticeStep(tick: 480, notes: [PracticeStepNote(midiNote: 62, staff: 1)]),
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
