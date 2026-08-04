import Foundation

public protocol BundledSongLibraryProviderProtocol: Sendable {
    func bundledEntries() -> [SongLibraryEntry]
    func musicXMLURL(fileName: String) -> URL?
    func audioURL(fileName: String) -> URL?
}
