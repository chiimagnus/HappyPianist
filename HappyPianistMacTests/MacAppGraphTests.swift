import Library
import Testing
@testable import HappyPianistMac

@MainActor
struct MacAppGraphTests {
    @Test func startsWithAnEmptyLibraryAndNoBundledScores() {
        let graph = MacAppGraph.make()

        #expect(graph.libraryEntryState == .empty)
        #expect(graph.bundledLibraryProvider.bundledEntries().isEmpty)
        #expect(graph.bundledLibraryProvider.musicXMLURL(fileName: "score.musicxml") == nil)
    }
}
