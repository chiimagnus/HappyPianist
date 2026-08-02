import Foundation

import UniformTypeIdentifiers

public struct ImportedMusicXMLFile: Equatable {
    public let fileName: String
    public let storedURL: URL
    public let importedAt: Date
}

extension UTType {
    public static var musicXML: UTType {
        UTType(importedAs: "com.recordare.musicxml")
    }

    public static var compressedMusicXML: UTType {
        UTType(importedAs: "com.recordare.musicxml.mxl")
    }
}
