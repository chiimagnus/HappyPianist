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
