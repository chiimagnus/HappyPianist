import Foundation

enum PracticeProgressLoadResult: Equatable, Sendable {
    case loaded(PracticeProgressDocument)
    case corrupted(description: String)
}

enum PracticeProgressRepositoryError: Error, Equatable {
    case corrupted(description: String)
}

protocol PracticeProgressRepositoryProtocol: Sendable {
    func load() async -> PracticeProgressLoadResult
    func progress(for identity: PracticeSongIdentity) async -> SongPracticeProgress?
    func upsert(_ progress: SongPracticeProgress) async throws
    func remove(songID: UUID) async throws
}

actor FilePracticeProgressRepository: PracticeProgressRepositoryProtocol {
    private let fileManager: FileManager
    private let paths: PracticeProgressPaths

    init(
        fileManager: FileManager = .default,
        paths: PracticeProgressPaths = PracticeProgressPaths()
    ) {
        self.fileManager = fileManager
        self.paths = paths
    }

    func load() -> PracticeProgressLoadResult {
        do {
            return .loaded(try loadDocument())
        } catch {
            return .corrupted(description: error.localizedDescription)
        }
    }

    func progress(for identity: PracticeSongIdentity) -> SongPracticeProgress? {
        guard case let .loaded(document) = load() else { return nil }
        return document.songs.first(where: { $0.identity == identity })
    }

    func upsert(_ progress: SongPracticeProgress) throws {
        var document = try loadDocument()
        if let index = document.songs.firstIndex(where: { $0.identity == progress.identity }) {
            document.songs[index] = progress
        } else {
            document.songs.append(progress)
        }
        document.songs.sort {
            if $0.identity.songID != $1.identity.songID {
                return $0.identity.songID.uuidString < $1.identity.songID.uuidString
            }
            return $0.identity.scoreRevision < $1.identity.scoreRevision
        }
        try saveDocument(document)
    }

    func remove(songID: UUID) throws {
        var document = try loadDocument()
        document.songs.removeAll(where: { $0.identity.songID == songID })
        try saveDocument(document)
    }

    private func loadDocument() throws -> PracticeProgressDocument {
        let fileURL = paths.fileURL
        guard fileManager.fileExists(atPath: fileURL.path()) else {
            return PracticeProgressDocument()
        }

        let data = try Data(contentsOf: fileURL)
        guard data.isEmpty == false,
              String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        else {
            return PracticeProgressDocument()
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(PracticeProgressDocument.self, from: data)
        } catch {
            throw PracticeProgressRepositoryError.corrupted(description: error.localizedDescription)
        }
    }

    private func saveDocument(_ document: PracticeProgressDocument) throws {
        try fileManager.createDirectory(at: paths.rootDirectoryURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(document).write(to: paths.fileURL, options: .atomic)
    }
}
