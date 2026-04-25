import CryptoKit
import Foundation

protocol BundledSongLibraryProviderProtocol {
    func bundledEntries() -> [SongLibraryEntry]
    func musicXMLURL(fileName: String) -> URL?
    func audioURL(fileName: String) -> URL?
}

struct BundledSongLibraryProvider: BundledSongLibraryProviderProtocol {
    private static let seedSubdirectory = "Resources/SeedScores"
    private static let bundledImportedAt = Date(timeIntervalSince1970: 0)

    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func bundledEntries() -> [SongLibraryEntry] {
        let urls = (bundle.urls(forResourcesWithExtension: "musicxml", subdirectory: Self.seedSubdirectory) ?? [])
            + (bundle.urls(forResourcesWithExtension: "musicxml", subdirectory: nil) ?? [])

        var byFileName: [String: URL] = [:]
        for url in urls {
            byFileName[url.lastPathComponent] = url
        }

        return byFileName
            .values
            .sorted { lhs, rhs in
                lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
            }
            .map { musicXMLURL in
                let fileName = musicXMLURL.lastPathComponent
                let baseName = musicXMLURL.deletingPathExtension().lastPathComponent
                let mp3FileName = "\(baseName).mp3"
                let audioExists = audioURL(fileName: mp3FileName) != nil

                return SongLibraryEntry(
                    id: DeterministicUUID.make(name: "bundled:\(fileName)"),
                    displayName: baseName,
                    musicXMLFileName: fileName,
                    importedAt: Self.bundledImportedAt,
                    audioFileName: audioExists ? mp3FileName : nil,
                    isBundled: true
                )
            }
    }

    func musicXMLURL(fileName: String) -> URL? {
        bundle.url(forResource: fileName, withExtension: nil, subdirectory: Self.seedSubdirectory)
            ?? bundle.url(forResource: fileName, withExtension: nil)
    }

    func audioURL(fileName: String) -> URL? {
        bundle.url(forResource: fileName, withExtension: nil, subdirectory: Self.seedSubdirectory)
            ?? bundle.url(forResource: fileName, withExtension: nil)
    }
}

enum DeterministicUUID {
    static func make(name: String) -> UUID {
        let digest = SHA256.hash(data: Data(name.utf8))
        let bytes = Array(digest)

        let b0 = bytes[0]
        let b1 = bytes[1]
        let b2 = bytes[2]
        let b3 = bytes[3]
        let b4 = bytes[4]
        let b5 = bytes[5]
        let b6 = (bytes[6] & 0x0F) | 0x50
        let b7 = bytes[7]
        let b8 = (bytes[8] & 0x3F) | 0x80
        let b9 = bytes[9]
        let b10 = bytes[10]
        let b11 = bytes[11]
        let b12 = bytes[12]
        let b13 = bytes[13]
        let b14 = bytes[14]
        let b15 = bytes[15]

        return UUID(uuid: (b0, b1, b2, b3, b4, b5, b6, b7, b8, b9, b10, b11, b12, b13, b14, b15))
    }
}

