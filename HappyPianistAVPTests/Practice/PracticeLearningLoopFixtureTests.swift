import Foundation
import MusicXML
import Practice
import Diagnostics
@testable import HappyPianistAVP
import Testing

@Test
func learningLoopFixtureCoversEightMeasuresStaffsTempoChordAndRepeatIdentity() throws {
    let fixtureURL = testFixtureURL("PracticeLearningLoopEightMeasures.musicxml")
    #expect(FileManager.default.fileExists(atPath: fixtureURL.path()))

    let parsed = try MusicXMLParser().parse(fileURL: fixtureURL)
    #expect(parsed.measures.count == 8)
    #expect(parsed.tempoEvents.contains(where: { $0.quarterBPM == 84 }))
    #expect(parsed.tempoEvents.contains(where: { $0.quarterBPM == 72 }))
    #expect(parsed.notes.contains(where: { $0.staff == 1 && $0.isRest == false }))
    #expect(parsed.notes.contains(where: { $0.staff == 2 && $0.isRest == false }))

    let handAssignments = MusicXMLHandRouter().assignments(for: parsed).assignmentsBySourceNoteID
    #expect(handAssignments.isEmpty)
    let writtenPlan = makeTestScorePerformancePlan(from: parsed, handAssignments: handAssignments)
    let writtenSteps = PracticeStepBuilder().buildSteps(from: writtenPlan).steps
    #expect(writtenSteps.flatMap(\.notes).allSatisfy { $0.hand == .unknown })

    let expanded = MusicXMLStructureExpander().expandRepeatAndEndingIfPossible(score: parsed)
    #expect(expanded.measures.count == 10)
    #expect(expanded.measures[0].sourceMeasureID == expanded.measures[2].sourceMeasureID)
    #expect(expanded.measures[0].occurrenceID != expanded.measures[2].occurrenceID)

    let expandedPlan = makeTestScorePerformancePlan(
        from: expanded,
        handAssignments: MusicXMLHandRouter().assignments(for: expanded).assignmentsBySourceNoteID
    )
    let steps = PracticeStepBuilder().buildSteps(from: expandedPlan).steps
    #expect(steps.isEmpty == false)
    #expect(steps.contains(where: { $0.notes.count >= 3 }))
}

@Test
func learningLoopFixtureIsIncludedInTestBundle() {
    let bundle = Bundle(for: PracticeLearningLoopFixtureBundleSentinel.self)
    let bundledURLs = (bundle.urls(
        forResourcesWithExtension: "musicxml",
        subdirectory: nil
    ) ?? []) + (bundle.urls(
        forResourcesWithExtension: "musicxml",
        subdirectory: "Fixtures"
    ) ?? [])
    #expect(
        bundledURLs.contains(where: { $0.lastPathComponent == "PracticeLearningLoopEightMeasures.musicxml" })
    )
}

private final class PracticeLearningLoopFixtureBundleSentinel: NSObject {}
