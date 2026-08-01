import Foundation

public struct SongLibraryEntry: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var displayName: String
    public var musicXMLFileName: String
    public var scoreFileVersionID: UUID
    public var importedAt: Date
    public var audioFileName: String?
    public var isBundled: Bool?

    public init(
        id: UUID,
        displayName: String,
        musicXMLFileName: String,
        scoreFileVersionID: UUID,
        importedAt: Date,
        audioFileName: String?,
        isBundled: Bool? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.musicXMLFileName = musicXMLFileName
        self.scoreFileVersionID = scoreFileVersionID
        self.importedAt = importedAt
        self.audioFileName = audioFileName
        self.isBundled = isBundled
    }
}

public struct SongLibraryIndex: Codable, Equatable, Sendable {
    public var entries: [SongLibraryEntry]
    public var lastSelectedEntryID: UUID?

    public init(entries: [SongLibraryEntry], lastSelectedEntryID: UUID? = nil) {
        self.entries = entries
        self.lastSelectedEntryID = lastSelectedEntryID
    }

    public static var empty: SongLibraryIndex {
        SongLibraryIndex(entries: [], lastSelectedEntryID: nil)
    }
}

public enum SongLibraryFileNameIdentity {
    public static func isExact(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf8.elementsEqual(rhs.utf8)
    }
}

public enum SongLibraryLayout {
    public static let rootDirectoryName = "SongLibrary"
    public static let scoresDirectoryName = "scores"
    public static let audioDirectoryName = "audio"
    public static let transactionsDirectoryName = "transactions"
    public static let indexFileName = "index.json"
}
