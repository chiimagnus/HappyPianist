import Foundation
import MusicXML
import Practice
import Testing

@Suite("Practice historical preferences resolver")
struct PracticeHistoricalPreferencesResolverTests {
    private let resolver = PracticeHistoricalPreferencesResolver()
    private let songID = UUID()

    @Test func exactIdentityWinsWithoutReturningHistoricalPreferences() async throws {
        let current = identity("current")
        let oldConfiguration = try configuration(hand: .left)
        let result = await resolve(current, progresses: [
            progress(revision: "old", updatedAt: 20, configuration: oldConfiguration),
            progress(revision: "current", updatedAt: 10, configuration: nil),
        ])

        #expect(result == .exactAvailable)
    }

    @Test func latestConfiguredIdentitySuppliesOnlyClampedUniversalValues() async throws {
        let oldFacts = MeasurePracticeFacts(
            sourceMeasureID: sourceMeasureID,
            handMode: .right,
            state: .pitchStepStable,
            successfulAttempts: 9,
            lastAttemptAt: Date(timeIntervalSince1970: 30)
        )
        let olderConfiguration = try configuration(hand: .right)
        let latestConfiguration = try configuration(
            hand: .left,
            tempo: 9,
            loop: true,
            successes: 99
        )
        let result = await resolve(identity("current"), progresses: [
            progress(revision: "older", updatedAt: 10, configuration: olderConfiguration),
            progress(
                revision: "latest",
                updatedAt: 20,
                configuration: latestConfiguration,
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

    @Test func duplicateIdentityUsesSharedRecordOrderAfterFilteringNilConfigurations() async throws {
        let leftConfiguration = try configuration(hand: .left)
        let rightConfiguration = try configuration(hand: .right)
        let result = await resolve(identity("current"), progresses: [
            progress(revision: "old", updatedAt: 30, configuration: nil),
            progress(revision: "old", updatedAt: 20, configuration: leftConfiguration),
            progress(revision: "old", updatedAt: 10, configuration: rightConfiguration),
        ])

        #expect(result == .historicalPreferences(PracticeHistoricalPreferences(
            handMode: .left,
            tempoScale: 0.8,
            loopEnabled: false,
            requiredSuccesses: 2
        )))
    }

    @Test func tiesAreDeterministicAcrossInputOrder() async throws {
        let lowerRevision = progress(
            revision: "a",
            updatedAt: 20,
            configuration: try configuration(hand: .right)
        )
        let higherRevision = progress(
            revision: "z",
            updatedAt: 20,
            configuration: try configuration(hand: .left)
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
    ) throws -> PracticeRoundConfiguration {
        PracticeRoundConfiguration(
            passage: try #require(PracticePassage(start: occurrenceID, end: occurrenceID)),
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
