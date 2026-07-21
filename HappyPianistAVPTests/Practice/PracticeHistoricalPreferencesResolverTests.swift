import Foundation
@testable import HappyPianistAVP
import Testing

@Suite("Practice historical preferences resolver")
struct PracticeHistoricalPreferencesResolverTests {
    private let resolver = PracticeHistoricalPreferencesResolver()
    private let songID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!

    @Test func exactIdentityWinsWithoutReturningHistoricalPreferences() async {
        let current = identity("current")
        let result = await resolve(current, progresses: [
            progress(revision: "old", updatedAt: 20, configuration: configuration(hand: .left)),
            progress(revision: "current", updatedAt: 10, configuration: nil),
        ])

        #expect(result == .exactAvailable)
    }

    @Test func latestConfiguredIdentitySuppliesOnlyClampedUniversalValues() async {
        let oldFacts = MeasurePracticeFacts(
            sourceMeasureID: sourceMeasureID,
            handMode: .right,
            state: .pitchStepStable,
            successfulAttempts: 9,
            lastAttemptAt: Date(timeIntervalSince1970: 30)
        )
        let result = await resolve(identity("current"), progresses: [
            progress(revision: "older", updatedAt: 10, configuration: configuration(hand: .right)),
            progress(
                revision: "latest",
                updatedAt: 20,
                configuration: configuration(
                    hand: .left,
                    tempo: 9,
                    loop: true,
                    successes: 99
                ),
                resumePoint: PracticeResumePoint(
                    occurrenceID: occurrenceID,
                    stepIndex: 88,
                    updatedAt: Date(timeIntervalSince1970: 20)
                ),
                facts: [oldFacts]
            ),
        ])

        #expect(result == .historicalPreferences(PracticeHistoricalPreferences(
            handMode: .left,
            tempoScale: 1,
            loopEnabled: true,
            requiredSuccesses: 5
        )))
    }

    @Test func duplicateIdentityUsesSharedRecordOrderAfterFilteringNilConfigurations() async {
        let result = await resolve(identity("current"), progresses: [
            progress(revision: "old", updatedAt: 30, configuration: nil),
            progress(revision: "old", updatedAt: 20, configuration: configuration(hand: .left)),
            progress(revision: "old", updatedAt: 10, configuration: configuration(hand: .right)),
        ])

        #expect(result == .historicalPreferences(PracticeHistoricalPreferences(
            handMode: .left,
            tempoScale: 0.8,
            loopEnabled: false,
            requiredSuccesses: 2
        )))
    }

    @Test func tiesAreDeterministicAcrossInputOrder() async {
        let lowerRevision = progress(
            revision: "a",
            updatedAt: 20,
            configuration: configuration(hand: .right)
        )
        let higherRevision = progress(
            revision: "z",
            updatedAt: 20,
            configuration: configuration(hand: .left)
        )

        let forward = await resolve(identity("current"), progresses: [lowerRevision, higherRevision])
        let reversed = await resolve(identity("current"), progresses: [higherRevision, lowerRevision])

        #expect(forward == reversed)
        #expect(forward == .historicalPreferences(PracticeHistoricalPreferences(
            handMode: .left,
            tempoScale: 0.8,
            loopEnabled: false,
            requiredSuccesses: 2
        )))
    }

    @Test func noConfiguredCandidateUsesFreshDefaults() async {
        let current = identity("current")
        let fresh = await resolve(current, progresses: [
            progress(revision: "old", updatedAt: 20, configuration: nil),
        ])

        #expect(fresh == .freshDefaults)
    }

    private func resolve(
        _ identity: PracticeSongIdentity,
        progresses: [SongPracticeProgress]
    ) async -> PracticeLaunchRestorePolicy {
        resolver.resolve(
            identity: identity,
            history: PracticeSongHistory(
                songID: songID,
                progresses: progresses,
                scoreMetadata: [],
                sessions: []
            )
        )
    }

    private func identity(_ revision: String) -> PracticeSongIdentity {
        PracticeSongIdentity(songID: songID, scoreRevision: revision)
    }

    private func progress(
        revision: String,
        updatedAt: TimeInterval,
        configuration: PracticeRoundConfiguration?,
        resumePoint: PracticeResumePoint? = nil,
        facts: [MeasurePracticeFacts] = []
    ) -> SongPracticeProgress {
        SongPracticeProgress(
            identity: identity(revision),
            activeConfiguration: configuration,
            resumePoint: resumePoint,
            measureFacts: facts,
            updatedAt: Date(timeIntervalSince1970: updatedAt)
        )
    }

    private func configuration(
        hand: PracticeHandMode,
        tempo: Double = 0.8,
        loop: Bool = false,
        successes: Int = 2
    ) -> PracticeRoundConfiguration {
        PracticeRoundConfiguration(
            passage: PracticePassage(start: occurrenceID, end: occurrenceID)!,
            handMode: hand,
            tempoScale: tempo,
            loopEnabled: loop,
            requiredSuccesses: successes
        )
    }

    private var sourceMeasureID: PracticeSourceMeasureID {
        PracticeSourceMeasureID(partID: "P1", sourceMeasureIndex: 0)
    }

    private var occurrenceID: PracticeMeasureOccurrenceID {
        PracticeMeasureOccurrenceID(sourceMeasureID: sourceMeasureID, occurrenceIndex: 0)
    }
}
