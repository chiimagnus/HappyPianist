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

@Test
func bundledProviderDiscoversNestedSeedScoresAndSiblingAudio() throws {
    let fileManager = FileManager.default
    let rootURL = fileManager.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let songDirectoryURL = rootURL
        .appending(path: "Nested Song", directoryHint: .isDirectory)
    try fileManager.createDirectory(at: songDirectoryURL, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: rootURL) }

    let musicXMLURL = songDirectoryURL.appending(path: "Nested Song.musicxml")
    let audioURL = songDirectoryURL.appending(path: "Nested Song.mp3")
    try Data("<score-partwise version=\"4.0\"/>".utf8).write(to: musicXMLURL)
    try Data([0]).write(to: audioURL)

    let provider = BundledSongLibraryProvider(seedRootURLs: [rootURL])
    let entry = try #require(provider.bundledEntries().first)

    #expect(provider.bundledEntries().count == 1)
    #expect(entry.displayName == "Nested Song")
    #expect(entry.musicXMLFileName == "Nested Song.musicxml")
    #expect(entry.audioFileName == "Nested Song.mp3")
    #expect(provider.musicXMLURL(fileName: entry.musicXMLFileName)?.standardizedFileURL == musicXMLURL.standardizedFileURL)
    #expect(provider.audioURL(fileName: entry.audioFileName ?? "")?.standardizedFileURL == audioURL.standardizedFileURL)
}
