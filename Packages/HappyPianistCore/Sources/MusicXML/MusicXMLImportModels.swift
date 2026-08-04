import Foundation

import UniformTypeIdentifiers

public struct ImportedMusicXMLFile: Equatable, Sendable {
    public let fileName: String
    public let storedURL: URL
    public let importedAt: Date

    public init(fileName: String, storedURL: URL, importedAt: Date) {
        self.fileName = fileName
        self.storedURL = storedURL
        self.importedAt = importedAt
    }
}

extension UTType {
    public static var musicXML: UTType {
        UTType(importedAs: "com.recordare.musicxml")
    }

    public static var compressedMusicXML: UTType {
        UTType(importedAs: "com.recordare.musicxml.mxl")
    }
}
