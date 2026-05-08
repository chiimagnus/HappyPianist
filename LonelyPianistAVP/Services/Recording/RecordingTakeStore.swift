import Foundation

protocol RecordingTakeStoreProtocol {
    func load() throws -> [RecordingTake]
    func save(_ takes: [RecordingTake]) throws
}

struct RecordingTakeStore: RecordingTakeStoreProtocol {
    private let fileManager: FileManager
    private let paths: RecordingTakeLibraryPaths

    init(fileManager: FileManager = .default, paths: RecordingTakeLibraryPaths? = nil) {
        self.fileManager = fileManager
        self.paths = paths ?? RecordingTakeLibraryPaths(fileManager: fileManager)
    }

    func load() throws -> [RecordingTake] {
        try paths.ensureDirectoriesExist()
        let takesFileURL = try paths.takesFileURL()

        guard fileManager.fileExists(atPath: takesFileURL.path()) else {
            return []
        }

        let data = try Data(contentsOf: takesFileURL)
        if data.isEmpty {
            return []
        }

        if let text = String(data: data, encoding: .utf8),
           text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([RecordingTake].self, from: data)
    }

    func save(_ takes: [RecordingTake]) throws {
        try paths.ensureDirectoriesExist()
        let takesFileURL = try paths.takesFileURL()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(takes)
        try data.write(to: takesFileURL, options: .atomic)
    }
}
