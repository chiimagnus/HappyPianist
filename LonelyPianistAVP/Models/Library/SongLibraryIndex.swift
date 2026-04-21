import Foundation

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
