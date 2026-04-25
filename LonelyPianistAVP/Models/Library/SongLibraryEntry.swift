import Foundation

struct SongLibraryEntry: Codable, Equatable, Identifiable {
    let id: UUID
    var displayName: String
    var musicXMLFileName: String
    var importedAt: Date
    var audioFileName: String?
    var isBundled: Bool? = nil
}
