import CryptoKit
import Foundation

protocol BundledSongLibraryProviderProtocol: Sendable {
    func bundledEntries() -> [SongLibraryEntry]
    func musicXMLURL(fileName: String) -> URL?
    func audioURL(fileName: String) -> URL?
}

struct BundledSongLibraryProvider: BundledSongLibraryProviderProtocol {
    private static let seedSubdirectory = "Resources/SeedScores"
    private static let bundledImportedAt = Date(timeIntervalSince1970: 0)

    private let bundle: Bundle
    private let seedRootURLsOverride: [URL]?

    init(bundle: Bundle = .main, seedRootURLs: [URL]? = nil) {
        self.bundle = bundle
        seedRootURLsOverride = seedRootURLs
    }

    func bundledEntries() -> [SongLibraryEntry] {
        var byFileName: [String: URL] = [:]
        for url in resourceURLs(withExtension: "musicxml") {
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
                let siblingAudioURL = musicXMLURL.deletingLastPathComponent().appending(path: mp3FileName)
                let audioExists = FileManager.default.fileExists(atPath: siblingAudioURL.path)
                    || audioURL(fileName: mp3FileName) != nil

                return SongLibraryEntry(
                    id: DeterministicUUID.make(name: "bundled:\(fileName)"),
                    displayName: baseName,
                    musicXMLFileName: fileName,
                    scoreFileVersionID: Self.scoreFileVersionID(
                        fileName: fileName,
                        bundleIdentifier: bundle.bundleIdentifier,
                        shortVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                        buildVersion: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
                    ),
                    importedAt: Self.bundledImportedAt,
                    audioFileName: audioExists ? mp3FileName : nil,
                    isBundled: true
                )
            }
    }

    func musicXMLURL(fileName: String) -> URL? {
        directResourceURL(fileName: fileName)
            ?? resourceURLs(withExtension: "musicxml").first { $0.lastPathComponent == fileName }
    }

    func audioURL(fileName: String) -> URL? {
        directResourceURL(fileName: fileName)
            ?? resourceURLs(withExtension: URL(fileURLWithPath: fileName).pathExtension)
                .first { $0.lastPathComponent == fileName }
    }

    private func directResourceURL(fileName: String) -> URL? {
        guard seedRootURLsOverride == nil else { return nil }
        return bundle.url(forResource: fileName, withExtension: nil, subdirectory: Self.seedSubdirectory)
            ?? bundle.url(forResource: fileName, withExtension: nil, subdirectory: "SeedScores")
            ?? bundle.url(forResource: fileName, withExtension: nil)
    }

    private func resourceURLs(withExtension fileExtension: String) -> [URL] {
        let normalizedExtension = fileExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedExtension.isEmpty == false else { return [] }

        var urls = seedRootURLs().flatMap {
            Self.recursiveResourceURLs(in: $0, withExtension: normalizedExtension)
        }
        if seedRootURLsOverride == nil {
            urls.append(contentsOf: bundle.urls(
                forResourcesWithExtension: normalizedExtension,
                subdirectory: Self.seedSubdirectory
            ) ?? [])
            urls.append(contentsOf: bundle.urls(
                forResourcesWithExtension: normalizedExtension,
                subdirectory: "SeedScores"
            ) ?? [])
            urls.append(contentsOf: bundle.urls(
                forResourcesWithExtension: normalizedExtension,
                subdirectory: nil
            ) ?? [])
        }
        var byPath: [String: URL] = [:]
        for url in urls {
            byPath[url.standardizedFileURL.path] = url
        }
        return byPath.values.sorted { $0.path < $1.path }
    }

    private func seedRootURLs() -> [URL] {
        if let seedRootURLsOverride {
            return seedRootURLsOverride
        }
        guard let resourceURL = bundle.resourceURL else { return [] }
        let candidates = [
            resourceURL.appending(path: Self.seedSubdirectory, directoryHint: .isDirectory),
            resourceURL.appending(path: "SeedScores", directoryHint: .isDirectory),
        ]
        return candidates.filter { candidate in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }
    }

    static func recursiveResourceURLs(in rootURL: URL, withExtension fileExtension: String) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator.compactMap { element -> URL? in
            guard let url = element as? URL,
                  url.pathExtension.localizedCaseInsensitiveCompare(fileExtension) == .orderedSame,
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            else {
                return nil
            }
            return url
        }
    }

    static func scoreFileVersionID(
        fileName: String,
        bundleIdentifier: String?,
        shortVersion: String?,
        buildVersion: String?
    ) -> UUID {
        let identity = bundleIdentifier ?? "<missing-bundle-identifier>"
        let version = shortVersion ?? "<missing-short-version>"
        let build = buildVersion ?? "<missing-build-version>"
        return DeterministicUUID.make(
            name: "bundled-version:\(identity)|\(version)|\(build)|\(fileName)"
        )
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
