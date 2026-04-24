import Foundation

protocol SongLibraryIndexStoreProtocol {
    func load() throws -> SongLibraryIndex
    func save(_ index: SongLibraryIndex) throws
}

struct SongLibraryIndexStore: SongLibraryIndexStoreProtocol {
    private let fileManager: FileManager
    private let paths: SongLibraryPaths

    init(fileManager: FileManager = .default, paths: SongLibraryPaths? = nil) {
        self.fileManager = fileManager
        self.paths = paths ?? SongLibraryPaths(fileManager: fileManager)
    }

    func load() throws -> SongLibraryIndex {
        try paths.ensureDirectoriesExist()
        let indexFileURL = try paths.indexFileURL()

        guard fileManager.fileExists(atPath: indexFileURL.path()) else {
            return .empty
        }

        let data = try Data(contentsOf: indexFileURL)
        if data.isEmpty {
            return .empty
        }

        if let text = String(data: data, encoding: .utf8),
           text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .empty
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SongLibraryIndex.self, from: data)
    }

    func save(_ index: SongLibraryIndex) throws {
        try paths.ensureDirectoriesExist()
        let indexFileURL = try paths.indexFileURL()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(index)
        try data.write(to: indexFileURL, options: .atomic)
    }
}
