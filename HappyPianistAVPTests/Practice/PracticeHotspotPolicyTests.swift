import Foundation
@testable import HappyPianistAVP
import Testing

@Test
func hotspotUsesFailuresRecencyThenPassageOrder() throws {
    let first = feedbackFacts(index: 1, failures: 2, issue: .wrongNote, date: Date(timeIntervalSince1970: 10))
    let recent = feedbackFacts(index: 2, failures: 2, issue: .incompleteChord, date: Date(timeIntervalSince1970: 20))

    let hotspot = try #require(PracticeHotspotPolicy().hotspot(in: [first, recent]))

    #expect(hotspot.sourceMeasureID == recent.sourceMeasureID)
}

@Test
func hotspotNeedsTypedIssueEvidence() {
    #expect(PracticeHotspotPolicy().hotspot(in: [feedbackFacts(index: 1, failures: 3)]) == nil)
}

func feedbackFacts(
    index: Int,
    handMode: PracticeHandMode = .both,
    state: MeasurePitchStepLearningState = .learning,
    failures: Int = 0,
    issue: PracticeIssueKind? = nil,
    date: Date? = nil
) -> MeasurePracticeFacts {
    MeasurePracticeFacts(
        sourceMeasureID: PracticeSourceMeasureID(partID: "P1", sourceMeasureIndex: index),
        handMode: handMode,
        state: state,
        failedAttempts: failures,
        recentIssue: issue,
        lastAttemptAt: date
    )
}
