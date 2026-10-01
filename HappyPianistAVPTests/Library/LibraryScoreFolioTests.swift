import Foundation
import Library
import SwiftUI
import Testing
@testable import HappyPianistAVP

@MainActor
@Test
func folioUsesSourceMetadataRatherThanGuessingFromSongTitle() throws {
    let entry = SongLibraryEntry(
        id: UUID(), displayName: "Bohemian_Rhapsody", musicXMLFileName: "score.musicxml",
        scoreFileVersionID: UUID(), importedAt: .now, audioFileName: nil, isBundled: false
    )
    let presentation = SongLibraryTrackPresentation(entry: entry, index: 0)
    #expect(presentation.title == "Bohemian Rhapsody")
    #expect(presentation.subtitle.hasPrefix("导入于"))
    #expect(!presentation.subtitle.contains("Queen"))
    let renderer = ImageRenderer(content: LibraryScoreFolioView(
        presentation: presentation, isPlaying: false
    ).frame(width: 200, height: 280))
    let image = try #require(renderer.cgImage)
    #expect(image.width == 200 && image.height == 280)
}
