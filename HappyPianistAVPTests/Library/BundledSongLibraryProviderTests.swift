import Foundation
@testable import HappyPianistAVP
import Testing

@Test
func deterministicBundledEntryIDsAreStableAndNameScoped() {
    let first = DeterministicUUID.make(name: "bundled:score.musicxml")
    let repeated = DeterministicUUID.make(name: "bundled:score.musicxml")
    let different = DeterministicUUID.make(name: "bundled:other.musicxml")

    #expect(first == repeated)
    #expect(first != different)
}

@Test
func bundledProviderPublishesUniqueStableEntryIDs() {
    let entries = BundledSongLibraryProvider().bundledEntries()

    #expect(Set(entries.map(\.id)).count == entries.count)
    #expect(entries.allSatisfy { $0.isBundled == true })
    for entry in entries {
        #expect(entry.id == DeterministicUUID.make(name: "bundled:\(entry.musicXMLFileName)"))
    }
}
