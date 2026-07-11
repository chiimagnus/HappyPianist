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
                roundGeneration: 1,
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
                roundGeneration: 1,
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
            roundGeneration: 1,
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
            roundGeneration: 1,
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
            roundGeneration: 1,
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
            roundGeneration: 1,
            measureIndex: fixture.measureIndex,
            timestamp: .now
        )

        let facts = try #require(repeatedFailure.progress.measureFacts.first)
        #expect(facts.successfulAttempts == 1)
        #expect(facts.failedAttempts == 1)
        #expect(facts.consecutiveSuccesses == 0)
        #expect(facts.recentIssue == .wrongNote)
    }

    @Test func insufficientEvidenceDoesNotCountAsFailure() throws {
        let fixture = try Fixture(requiredSuccesses: 3)
        let reducer = PracticeAttemptReducer()
        let result = reducer.reduceAttempt(
            progress: nil,
            reductionState: .init(),
            outcome: fixture.insufficient(stepIndex: 0),
            stepIndex: 0,
            identity: fixture.identity,
            configuration: fixture.configuration,
            roundGeneration: 1,
            measureIndex: fixture.measureIndex,
            timestamp: .now
        )

        let facts = try #require(result.progress.measureFacts.first)
        #expect(facts.failedAttempts == 0)
        #expect(facts.successfulAttempts == 0)
        #expect(result.fact == nil)
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

    func matched(stepIndex: Int) -> StepAttemptMatchResult {
        .matched(evidence: evidence(stepIndex: stepIndex, observed: [60 + stepIndex * 2]))
    }

    func wrong(stepIndex: Int) -> StepAttemptMatchResult {
        .wrongNote(
            evidence: evidence(stepIndex: stepIndex, observed: [71]),
            unexpectedNotes: [71]
        )
    }

    func insufficient(stepIndex: Int) -> StepAttemptMatchResult {
        .insufficientEvidence(evidence: evidence(stepIndex: stepIndex, observed: []))
    }

    private func evidence(stepIndex: Int, observed: Set<Int>) -> PracticeAttemptEvidence {
        PracticeAttemptEvidence(
            expectedNotes: [60 + stepIndex * 2],
            observedNotes: observed,
            handMode: .right,
            source: .midi,
            isPartialEvidence: false,
            debugMessage: "fixture"
        )
    }
}
