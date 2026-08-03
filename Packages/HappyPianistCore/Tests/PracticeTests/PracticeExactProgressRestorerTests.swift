import Foundation
@testable import MusicXML
import Practice
import Testing

struct PracticeExactProgressRestorerTests {
    @Test func exactConfigurationAndResumeRemainIntact() throws {
        let fixture = try RestoreFixture()
        let configuration = fixture.configuration(
            passage: fixture.fullPassage,
            handMode: .left
        )
        let progress = SongPracticeProgress(
            identity: fixture.identity,
            activeConfiguration: configuration,
            resumePoint: PracticeResumePoint(
                occurrenceID: fixture.spans[1].occurrenceID,
                stepIndex: 1,
                updatedAt: .now
            ),
            updatedAt: .now
        )

        let restoration = PracticeExactProgressRestorer.restore(
            progress,
            freshConfiguration: fixture.freshConfiguration,
            measureIndex: fixture.measureIndex
        )

        #expect(restoration.progress == progress)
        #expect(restoration.activeRange?.passage == configuration.passage)
        #expect(restoration.activeRangeDiagnostic == nil)
        #expect(restoration.didRepairSavedState == false)
    }

    @Test func invalidPassageRepairsToFreshConfigurationWithoutLosingFacts() throws {
        let fixture = try RestoreFixture()
        let missingSource = PracticeSourceMeasureID(
            partID: "P1",
            sourceMeasureIndex: 99,
            sourceNumberToken: "100"
        )
        let missingOccurrence = PracticeMeasureOccurrenceID(
            sourceMeasureID: missingSource,
            occurrenceIndex: 99
        )
        let invalidPassage = try #require(PracticePassage(
            start: missingOccurrence,
            end: missingOccurrence
        ))
        let retainedFact = MeasurePracticeFacts(
            sourceMeasureID: fixture.spans[0].occurrenceID.sourceMeasureID,
            handMode: .both,
            state: .learning,
            successfulAttempts: 1
        )
        let progress = SongPracticeProgress(
            identity: fixture.identity,
            activeConfiguration: fixture.configuration(passage: invalidPassage),
            resumePoint: PracticeResumePoint(
                occurrenceID: missingOccurrence,
                stepIndex: 99,
                updatedAt: .now
            ),
            measureFacts: [retainedFact],
            updatedAt: .now
        )

        let restoration = PracticeExactProgressRestorer.restore(
            progress,
            freshConfiguration: fixture.freshConfiguration,
            measureIndex: fixture.measureIndex
        )

        #expect(restoration.progress.activeConfiguration == fixture.freshConfiguration)
        #expect(restoration.progress.resumePoint == nil)
        #expect(restoration.progress.measureFacts == [retainedFact])
        #expect(restoration.activeRange?.passage == fixture.freshConfiguration.passage)
        #expect(restoration.activeRangeDiagnostic == nil)
        #expect(restoration.didRepairSavedState)
    }

    @Test func resumeOutsideTheActivePassageIsClearedWithoutLosingFacts() throws {
        let fixture = try RestoreFixture()
        let firstPassage = try #require(PracticePassage(
            start: fixture.spans[0].occurrenceID,
            end: fixture.spans[0].occurrenceID
        ))
        let retainedFact = MeasurePracticeFacts(
            sourceMeasureID: fixture.spans[0].occurrenceID.sourceMeasureID,
            handMode: .both,
            state: .learning,
            successfulAttempts: 1
        )
        let progress = SongPracticeProgress(
            identity: fixture.identity,
            activeConfiguration: fixture.configuration(passage: firstPassage),
            resumePoint: PracticeResumePoint(
                occurrenceID: fixture.spans[1].occurrenceID,
                stepIndex: 1,
                updatedAt: .now
            ),
            measureFacts: [retainedFact],
            updatedAt: .now
        )

        let restoration = PracticeExactProgressRestorer.restore(
            progress,
            freshConfiguration: fixture.freshConfiguration,
            measureIndex: fixture.measureIndex
        )

        #expect(restoration.progress.activeConfiguration == progress.activeConfiguration)
        #expect(restoration.progress.resumePoint == nil)
        #expect(restoration.progress.measureFacts == [retainedFact])
        #expect(restoration.activeRange?.passage == firstPassage)
        #expect(restoration.didRepairSavedState)
    }
}

private struct RestoreFixture {
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "r1")
    let spans: [MusicXMLMeasureSpan]
    let measureIndex: PracticeMeasureIndex
    let fullPassage: PracticePassage
    let freshConfiguration: PracticeRoundConfiguration

    init() throws {
        spans = [
            MusicXMLMeasureSpan(
                partID: "P1",
                measureNumber: 1,
                sourceMeasureIndex: 0,
                sourceMeasureNumberToken: "1",
                occurrenceIndex: 0,
                startTick: 0,
                endTick: 480
            ),
            MusicXMLMeasureSpan(
                partID: "P1",
                measureNumber: 2,
                sourceMeasureIndex: 1,
                sourceMeasureNumberToken: "2",
                occurrenceIndex: 1,
                startTick: 480,
                endTick: 960
            ),
        ]
        measureIndex = PracticeMeasureIndex(
            steps: [
                PracticeStep(
                    tick: 0,
                    notes: [PracticeStepNote(
                        midiNote: 60,
                        staff: 1,
                        handAssignment: .unknown
                    )]
                ),
                PracticeStep(
                    tick: 480,
                    notes: [PracticeStepNote(
                        midiNote: 62,
                        staff: 1,
                        handAssignment: .unknown
                    )]
                ),
            ],
            measureSpans: spans
        )
        fullPassage = try #require(PracticePassage(
            start: spans[0].occurrenceID,
            end: spans[1].occurrenceID
        ))
        freshConfiguration = PracticeRoundConfiguration(
            passage: fullPassage,
            handMode: .both,
            tempoScale: 0.8,
            loopEnabled: true,
            requiredSuccesses: 3
        )
    }

    func configuration(
        passage: PracticePassage,
        handMode: PracticeHandMode = .both
    ) -> PracticeRoundConfiguration {
        PracticeRoundConfiguration(
            passage: passage,
            handMode: handMode,
            tempoScale: 0.8,
            loopEnabled: true,
            requiredSuccesses: 3
        )
    }
}
