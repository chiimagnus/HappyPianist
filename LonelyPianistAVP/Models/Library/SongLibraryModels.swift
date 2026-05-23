import Foundation

struct SongLibraryEntry: Codable, Equatable, Identifiable {
    let id: UUID
    var displayName: String
    var musicXMLFileName: String
    var importedAt: Date
    var audioFileName: String?
    var isBundled: Bool? = nil
}

struct SongLibraryIndex: Codable, Equatable {
    var entries: [SongLibraryEntry]
    var lastSelectedEntryID: UUID?

    static var empty: SongLibraryIndex {
        SongLibraryIndex(entries: [], lastSelectedEntryID: nil)
    }
}

enum SongLibraryLayout {
    static let rootDirectoryName = "SongLibrary"
    static let scoresDirectoryName = "scores"
    static let audioDirectoryName = "audio"
    static let indexFileName = "index.json"
}
