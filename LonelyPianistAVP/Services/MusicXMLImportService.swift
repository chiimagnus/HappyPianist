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
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func importFile(from sourceURL: URL) throws -> ImportedMusicXMLFile {
        let hasScopedAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasScopedAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
        guard let documentsURL else {
            throw CocoaError(.fileNoSuchFile)
        }

        let importDirectory = documentsURL.appendingPathComponent("ImportedScores", isDirectory: true)
        try fileManager.createDirectory(at: importDirectory, withIntermediateDirectories: true)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let destinationURL = importDirectory.appendingPathComponent("\(timestamp)-\(sourceURL.lastPathComponent)")

        if fileManager.fileExists(atPath: destinationURL.path()) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        return ImportedMusicXMLFile(
            fileName: sourceURL.lastPathComponent,
            storedURL: destinationURL,
            importedAt: Date()
        )
    }
}

extension UTType {
    static var musicXML: UTType {
        UTType(importedAs: "com.recordare.musicxml")
    }
}
