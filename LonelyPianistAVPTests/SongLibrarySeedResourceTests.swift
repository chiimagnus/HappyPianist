import Foundation
@testable import LonelyPianistAVP
import Testing

@Test
func songLibrarySeedResourceExistsAndCanBuildPracticeSteps() throws {
    let bundle = Bundle(for: SongLibrarySeeder.self)

    let seedURL = bundle.url(
        forResource: SongLibrarySeeder.seedFileName,
        withExtension: nil,
        subdirectory: SongLibrarySeeder.seedSubdirectory
    ) ?? bundle.url(forResource: SongLibrarySeeder.seedFileName, withExtension: nil)

    #expect(seedURL != nil)

    guard let seedURL else { return }

    let score = try MusicXMLParser().parse(fileURL: seedURL)
    let buildResult = PracticeStepBuilder().buildSteps(from: score)

    #expect(buildResult.steps.isEmpty == false)

    let audioURL = bundle.url(
        forResource: SongLibrarySeeder.seedAudioFileName,
        withExtension: nil,
        subdirectory: SongLibrarySeeder.seedSubdirectory
    ) ?? bundle.url(forResource: SongLibrarySeeder.seedAudioFileName, withExtension: nil)
    #expect(audioURL != nil)
}
