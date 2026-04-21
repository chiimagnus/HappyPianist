import Foundation
import UniformTypeIdentifiers

struct ImportedMusicXMLFile: Equatable {
    let fileName: String
    let storedURL: URL
    let importedAt: Date
}

protocol MusicXMLImportServiceProtocol {
    func importFile(from sourceURL: URL) throws -> ImportedMusicXMLFile
}

struct MusicXMLImportService: MusicXMLImportServiceProtocol {
    private let fileStore: SongFileStoreProtocol

    init(fileManager: FileManager = .default) {
        let paths = SongLibraryPaths(fileManager: fileManager)
        self.fileStore = SongFileStore(fileManager: fileManager, paths: paths)
    }

    func importFile(from sourceURL: URL) throws -> ImportedMusicXMLFile {
        let imported = try fileStore.importMusicXML(from: sourceURL)

        return ImportedMusicXMLFile(
            fileName: imported.sourceFileName,
            storedURL: imported.storedURL,
            importedAt: imported.importedAt
        )
    }
}

extension UTType {
    static var musicXML: UTType {
        UTType(importedAs: "com.recordare.musicxml")
    }
}
