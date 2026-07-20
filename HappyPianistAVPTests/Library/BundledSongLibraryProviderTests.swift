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
func bundledProviderPreservesNestedRelativePathIdentityAndSiblingAudio() throws {
    let fileManager = FileManager.default
    let rootURL = fileManager.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? fileManager.removeItem(at: rootURL) }

    let firstDirectoryURL = rootURL.appending(path: "First", directoryHint: .isDirectory)
    let secondDirectoryURL = rootURL.appending(path: "Second", directoryHint: .isDirectory)
    try fileManager.createDirectory(at: firstDirectoryURL, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: secondDirectoryURL, withIntermediateDirectories: true)

    let firstMusicXMLURL = firstDirectoryURL.appending(path: "Shared.musicxml")
    let secondMusicXMLURL = secondDirectoryURL.appending(path: "Shared.musicxml")
    let firstAudioURL = firstDirectoryURL.appending(path: "Shared.mp3")
    let secondAudioURL = secondDirectoryURL.appending(path: "Shared.mp3")
    try Data("<score-partwise version=\"4.0\"/>".utf8).write(to: firstMusicXMLURL)
    try Data("<score-partwise version=\"4.0\"/>".utf8).write(to: secondMusicXMLURL)
    try Data([0]).write(to: firstAudioURL)
    try Data([1]).write(to: secondAudioURL)

    let provider = BundledSongLibraryProvider(seedRootURLs: [rootURL])
    let entries = provider.bundledEntries()
    let firstEntry = try #require(entries.first { $0.musicXMLFileName == "First/Shared.musicxml" })
    let secondEntry = try #require(entries.first { $0.musicXMLFileName == "Second/Shared.musicxml" })

    #expect(entries.count == 2)
    #expect(firstEntry.id != secondEntry.id)
    #expect(firstEntry.audioFileName == "First/Shared.mp3")
    #expect(secondEntry.audioFileName == "Second/Shared.mp3")
    #expect(provider.musicXMLURL(fileName: firstEntry.musicXMLFileName)?.standardizedFileURL == firstMusicXMLURL.standardizedFileURL)
    #expect(provider.musicXMLURL(fileName: secondEntry.musicXMLFileName)?.standardizedFileURL == secondMusicXMLURL.standardizedFileURL)
    #expect(provider.audioURL(fileName: firstEntry.audioFileName ?? "")?.standardizedFileURL == firstAudioURL.standardizedFileURL)
    #expect(provider.audioURL(fileName: secondEntry.audioFileName ?? "")?.standardizedFileURL == secondAudioURL.standardizedFileURL)
}
