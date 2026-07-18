import Foundation
@testable import HappyPianistAVP
import Testing

@Test
func parsedMeasuresKeepSourceIndexAndNumberToken() throws {
    let score = try MusicXMLParser().parse(fileURL: testFixtureURL("PracticeMeasureIdentityRepeats.musicxml"))

    #expect(score.measures.map(\.sourceMeasureIndex) == [1, 2, 3])
    #expect(score.measures.map(\.sourceMeasureNumberToken) == ["1A", "2", "2"])
    #expect(score.measures.map(\.occurrenceIndex) == [0, 1, 2])
}

@Test
func expandedMeasuresKeepSourceIdentityAcrossOccurrences() throws {
    let score = try MusicXMLParser().parse(fileURL: testFixtureURL("PracticeMeasureIdentityRepeats.musicxml"))
    let expanded = MusicXMLStructureExpander().expandRepeatAndEndingIfPossible(score: score)

    #expect(expanded.measures.map(\.sourceMeasureIndex) == [1, 2, 1, 3])
    #expect(expanded.measures.map(\.sourceMeasureNumberToken) == ["1A", "2", "1A", "2"])
    #expect(expanded.measures.map(\.occurrenceIndex) == [0, 1, 2, 3])
    #expect(expanded.measures.map(\.measureNumber) == [1, 2, 3, 4])
    #expect(expanded.measures[0].sourceMeasureID == expanded.measures[2].sourceMeasureID)
    #expect(expanded.measures[0].occurrenceID != expanded.measures[2].occurrenceID)
}

@Test
func parsedNotesReceiveStableSourceIdentityIndependentOfPerformanceFields() throws {
    let scoreA = try MusicXMLParser().parse(fileURL: testFixtureURL("PracticeMeasureIdentityRepeats.musicxml"))
    let scoreB = try MusicXMLParser().parse(fileURL: testFixtureURL("PracticeMeasureIdentityRepeats.musicxml"))

    #expect(scoreA.notes.map(\.sourceID) == scoreB.notes.map(\.sourceID))
    #expect(scoreA.notes.allSatisfy { $0.sourceID != nil })
    #expect(scoreA.notes.allSatisfy { $0.performedOccurrenceIndex == 0 })
    #expect(Set(scoreA.notes.compactMap(\.sourceID)).count == scoreA.notes.count)
}

@Test
func expandedNotesKeepTheirSourceIdentityAcrossPerformedOccurrences() throws {
    let score = try MusicXMLParser().parse(fileURL: testFixtureURL("PracticeMeasureIdentityRepeats.musicxml"))
    let expanded = MusicXMLStructureExpander().expandRepeatAndEndingIfPossible(score: score)
    let repeatedSourceIDs = Dictionary(grouping: expanded.notes.compactMap(\.sourceID), by: { $0 })

    #expect(repeatedSourceIDs.values.contains { $0.count > 1 })
    #expect(expanded.notes.map(\.performedOccurrenceIndex) == [0, 1, 2, 3])
    #expect(Set(expanded.notes.compactMap(\.performedID)).count == expanded.notes.count)
    #expect(expanded.notes.allSatisfy { note in
        note.performedID?.sourceID == note.sourceID
    })
}
