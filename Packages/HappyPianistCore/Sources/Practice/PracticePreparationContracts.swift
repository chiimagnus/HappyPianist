import Foundation
import MusicXML

public struct PracticeSongIdentity: Codable, Equatable, Hashable, Sendable {
    public let songID: UUID
    public let scoreRevision: String

    public init(songID: UUID, scoreRevision: String) {
        self.songID = songID
        self.scoreRevision = scoreRevision
    }
}

public struct PracticePreparationOptions: Equatable, Sendable {
    public let scoreOrder: MusicXMLScoreOrder

    public init(scoreOrder: MusicXMLScoreOrder) {
        self.scoreOrder = scoreOrder
    }

    public static let practice = PracticePreparationOptions(
        scoreOrder: MusicXMLRealisticPlaybackDefaults.practiceScoreOrder
    )
    public static let referencePlayback = PracticePreparationOptions(
        scoreOrder: MusicXMLRealisticPlaybackDefaults.referencePlaybackScoreOrder
    )
}
