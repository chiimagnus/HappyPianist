import Foundation
@testable import HappyPianistAVP
import Testing

@Test
func duetQualityRegressionFixtureBandsRemainStable() {
    for fixture in DuetQualityRegressionFixtures.all {
        let assessment = DuetPhrasePolicy.assessSchedule(
            fixture.rawSchedule,
            noteSnapshot: fixture.noteSnapshot,
            horizonSeconds: fixture.horizonSeconds
        )
        #expect(assessment.band == fixture.expectedBand)
    }
}

@Test
func duetQualityRegressionShapingOutcomesRemainStable() {
    let acceptable = DuetQualityRegressionFixtures.acceptableSupport
    let acceptableShaped = DuetPhrasePolicy.shapeSchedule(
        acceptable.rawSchedule,
        noteSnapshot: acceptable.noteSnapshot,
        controlMode: .support,
        horizonSeconds: acceptable.horizonSeconds
    )
    #expect(acceptableShaped.isEmpty == false)

    let risky = DuetQualityRegressionFixtures.riskyRepetition
    let riskyShaped = DuetPhrasePolicy.shapeSchedule(
        risky.rawSchedule,
        noteSnapshot: risky.noteSnapshot,
        controlMode: .support,
        horizonSeconds: risky.horizonSeconds
    )
    #expect(riskyShaped.isEmpty == false)
    let riskyAssessment = DuetPhrasePolicy.assessSchedule(
        riskyShaped,
        noteSnapshot: risky.noteSnapshot,
        horizonSeconds: risky.horizonSeconds
    )
    #expect(riskyAssessment.band != .reject)

    for rejectingFixture in [
        DuetQualityRegressionFixtures.registerClash,
        DuetQualityRegressionFixtures.denseBurst,
        DuetQualityRegressionFixtures.fragmentedHint,
    ] {
        let shaped = DuetPhrasePolicy.shapeSchedule(
            rejectingFixture.rawSchedule,
            noteSnapshot: rejectingFixture.noteSnapshot,
            controlMode: .support,
            horizonSeconds: rejectingFixture.horizonSeconds
        )
        #expect(shaped.isEmpty)
    }
}

@Test
func improvQualityRubricDefaultFixtureIsVersionedAndEvidenceAware() {
    let fixture = ImprovQualityRubric.defaultFixture
    let assessment = ImprovQualityRubric().assess(
        fixture.response,
        responseLatencySeconds: fixture.responseLatencySeconds
    )

    #expect(assessment.thresholdVersion == ImprovQualityRubric.Thresholds.v2.version)
    #expect(assessment.band == .acceptable)
    #expect(ImprovQualityRubric.Dimension.allCases.allSatisfy { assessment.dimensions[$0] != nil })
    #expect(assessment.dimensions[.harmonicFit] == .notObserved)
    #expect(assessment.dimensions[.cadence] == .notObserved)
    #expect(assessment.dimensions[.responseLatency] == .pass)
}

@Test
func improvQualityRubricRejectsUnusableResponseBeforePlayback() {
    let invalidResponse = [
        PracticeSequencerMIDIEvent(timeSeconds: 0, kind: .noteOn(midi: 12, velocity: 90)),
        PracticeSequencerMIDIEvent(timeSeconds: 0.2, kind: .noteOff(midi: 12)),
    ]
    let assessment = ImprovQualityRubric().assess(invalidResponse)
    #expect(assessment.band == .reject)
    #expect(assessment.reasons.contains(.outOfPianoRegister))

    let schedule = ImprovScheduleBuilder().buildSchedule(
        from: [.note(note: 12, velocity: 90, time: 0, duration: 0.2)],
        leadInSeconds: 0
    )
    #expect(schedule.isEmpty)
}

@Test
func improvQualityRubricPhraseFixturesRemainExplainable() {
    for fixture in DuetQualityRegressionFixtures.rubricAll {
        let assessment = ImprovQualityRubric().assess(fixture.response, context: fixture.context)
        #expect(assessment.band == fixture.expectedBand, "fixture=\(fixture.name)")
        if let expectedReason = fixture.expectedReason {
            #expect(assessment.reasons.contains(expectedReason), "fixture=\(fixture.name)")
        }
        if let expectedCadenceEvidence = fixture.expectedCadenceEvidence {
            #expect(assessment.dimensions[.cadence] == expectedCadenceEvidence, "fixture=\(fixture.name)")
        }
    }
}
