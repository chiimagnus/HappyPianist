import Foundation

struct SongLibraryEntry: Codable, Equatable, Identifiable {
    let id: UUID
    var displayName: String
    var musicXMLFileName: String
    var scoreFileVersionID: UUID
    var importedAt: Date
    var audioFileName: String?
    var isBundled: Bool?

    init(
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

struct SongLibraryIndex: Codable, Equatable {
    var entries: [SongLibraryEntry]
    var lastSelectedEntryID: UUID?

    static var empty: SongLibraryIndex {
        SongLibraryIndex(entries: [], lastSelectedEntryID: nil)
    }
}

enum SongLibraryFileNameIdentity {
    static func isExact(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf8.elementsEqual(rhs.utf8)
    }
}

enum SongLibraryLayout {
    static let rootDirectoryName = "SongLibrary"
    static let scoresDirectoryName = "scores"
    static let audioDirectoryName = "audio"
    static let transactionsDirectoryName = "transactions"
    static let indexFileName = "index.json"
}
