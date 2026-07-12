import Foundation
import UniformTypeIdentifiers

struct ImportedMusicXMLFile: Equatable {
    let fileName: String
    let storedURL: URL
    let importedAt: Date
}

extension UTType {
    static var musicXML: UTType {
        UTType(importedAs: "com.recordare.musicxml")
    }

    static var compressedMusicXML: UTType {
        UTType(importedAs: "com.recordare.musicxml.mxl")
    }
}
