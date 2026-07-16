import Foundation
@testable import HappyPianistAVP
import Testing

@Test
func learningLoopFixtureCoversEightMeasuresHandsTempoChordAndRepeatIdentity() throws {
    let fixtureURL = testFixtureURL("PracticeLearningLoopEightMeasures.musicxml")
    #expect(FileManager.default.fileExists(atPath: fixtureURL.path()))

    let parsed = try MusicXMLParser().parse(fileURL: fixtureURL)
    #expect(parsed.measures.count == 8)
    #expect(parsed.tempoEvents.contains(where: { $0.quarterBPM == 84 }))
    #expect(parsed.tempoEvents.contains(where: { $0.quarterBPM == 72 }))
    #expect(parsed.notes.contains(where: { $0.staff == 1 && $0.isRest == false }))
    #expect(parsed.notes.contains(where: { $0.staff == 2 && $0.isRest == false }))

    let routed = MusicXMLHandRouter().routeIfNeeded(score: parsed)
    let routedSteps = PracticeStepBuilder().buildSteps(from: routed).steps
    #expect(routedSteps.flatMap(\.notes).contains(where: { $0.hand == .right }))
    #expect(routedSteps.flatMap(\.notes).contains(where: { $0.hand == .left }))

    let expanded = MusicXMLStructureExpander().expandRepeatAndEndingIfPossible(score: routed)
    #expect(expanded.measures.count == 10)
    #expect(expanded.measures[0].sourceMeasureID == expanded.measures[2].sourceMeasureID)
    #expect(expanded.measures[0].occurrenceID != expanded.measures[2].occurrenceID)

    let steps = PracticeStepBuilder().buildSteps(from: expanded).steps
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
