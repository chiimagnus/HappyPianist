import Foundation

enum PracticeProgressLoadResult: Equatable, Sendable {
    case loaded(PracticeProgressDocument)
    case unavailable(description: String)
    case corrupted(description: String)
}

enum PracticeProgressRepositoryError: Error, Equatable, Sendable {
    case unavailable(description: String)
    case corrupted(description: String)
}

enum PracticeProgressRecoveryResult: Equatable, Sendable {
    case recovered(backupURL: URL)
    case notNeeded
}

protocol PracticeProgressRepositoryProtocol: Sendable {
    func load() async -> PracticeProgressLoadResult
    func progress(for identity: PracticeSongIdentity) async -> SongPracticeProgress?
    func history(for songID: UUID) async -> PracticeSongHistoryLoadResult
    func upsert(_ progress: SongPracticeProgress) async throws
    func upsert(_ metadata: SongScorePracticeMetadata) async throws
    func remove(songID: UUID) async throws
}

protocol PracticeProgressRecoveryProtocol: Sendable {
    func recoverFromCorruption() async throws -> PracticeProgressRecoveryResult
}

typealias PracticeProgressFileReplacement = @Sendable (
    _ fileManager: FileManager,
    _ originalURL: URL,
    _ stagingURL: URL,
    _ backupName: String
) throws -> Void

actor FilePracticeProgressRepository: PracticeProgressRepositoryProtocol, PracticeProgressRecoveryProtocol {
    private let fileManager: FileManager
    private let paths: PracticeProgressPaths
    private let replaceFile: PracticeProgressFileReplacement

    init(
        fileManager: FileManager = .default,
        paths: PracticeProgressPaths = PracticeProgressPaths(),
        replaceFile: @escaping PracticeProgressFileReplacement = { fileManager, originalURL, stagingURL, backupName in
            _ = try fileManager.replaceItemAt(
                originalURL,
                withItemAt: stagingURL,
                backupItemName: backupName,
                options: [.usingNewMetadataOnly, .withoutDeletingBackupItem]
            )
        }
    ) {
        self.fileManager = fileManager
        self.paths = paths
        self.replaceFile = replaceFile
    }

    func load() -> PracticeProgressLoadResult {
        do {
            return .loaded(try loadDocument())
        } catch let error as PracticeProgressRepositoryError {
            switch error {
            case let .unavailable(description):
                return .unavailable(description: description)
            case let .corrupted(description):
                return .corrupted(description: description)
            }
        } catch {
            return .unavailable(description: Self.safeDescription(error))
        }
    }

    func progress(for identity: PracticeSongIdentity) -> SongPracticeProgress? {
        guard case let .loaded(document) = load() else { return nil }
        return PracticeProgressRecordOrder.preferred(
            in: document.songs.filter { $0.identity == identity }
        )
    }

    func history(for songID: UUID) -> PracticeSongHistoryLoadResult {
        switch load() {
        case let .loaded(document):
            return .loaded(
                PracticeSongHistory(
                    songID: songID,
                    progresses: PracticeProgressRecordOrder.sorted(
                        document.songs.filter { $0.identity.songID == songID }
                    ),
                    scoreMetadata: Self.sortedMetadata(
                        document.scoreMetadata.filter { $0.songID == songID }
                    )
                )
            )
        case let .unavailable(description):
            return .unavailable(description: description)
        case let .corrupted(description):
            return .corrupted(description: description)
        }
    }

    func upsert(_ progress: SongPracticeProgress) throws {
        var document = try loadDocument()
        document.songs.removeAll { $0.identity == progress.identity }
        document.songs.append(progress)
        document.songs = PracticeProgressRecordOrder.sorted(document.songs)
        try saveDocument(document)
    }

    func upsert(_ metadata: SongScorePracticeMetadata) throws {
        var document = try loadDocument()
        let sameIdentity = document.scoreMetadata.filter {
            $0.songID == metadata.songID
                && $0.scoreFileVersionID == metadata.scoreFileVersionID
                && $0.scoreRevision == metadata.scoreRevision
        }
        document.scoreMetadata.removeAll {
            $0.songID == metadata.songID
                && $0.scoreFileVersionID == metadata.scoreFileVersionID
                && $0.scoreRevision == metadata.scoreRevision
        }
        document.scoreMetadata.append(
            SongScorePracticeMetadataOrder.preferred(in: sameIdentity + [metadata]) ?? metadata
        )
        document.scoreMetadata = Self.sortedMetadata(document.scoreMetadata)
        try saveDocument(document)
    }

    func remove(songID: UUID) throws {
        var document = try loadDocument()
        document.songs.removeAll(where: { $0.identity.songID == songID })
        document.scoreMetadata.removeAll(where: { $0.songID == songID })
        try saveDocument(document)
    }

    func recoverFromCorruption() throws -> PracticeProgressRecoveryResult {
        do {
            _ = try loadDocument()
            return .notNeeded
        } catch PracticeProgressRepositoryError.corrupted {
            // Continue only for confirmed schema corruption.
        }

        let recoveryID = UUID()
        let stagingURL = paths.recoveryStagingURL(id: recoveryID)
        let backupURL = paths.recoveryBackupURL(id: recoveryID)
        defer { try? fileManager.removeItem(at: stagingURL) }

        do {
            try fileManager.createDirectory(at: paths.rootDirectoryURL, withIntermediateDirectories: true)
            let data = try encodedDocument(PracticeProgressDocument())
            try data.write(to: stagingURL, options: .atomic)
            _ = try decodedDocument(from: Data(contentsOf: stagingURL))
            try replaceFile(
                fileManager,
                paths.fileURL,
                stagingURL,
                paths.recoveryBackupName(id: recoveryID)
            )
            return .recovered(backupURL: backupURL)
        } catch {
            throw PracticeProgressRepositoryError.unavailable(
                description: Self.safeDescription(error)
            )
        }
    }

    private func loadDocument() throws -> PracticeProgressDocument {
        let data: Data
        do {
            data = try Data(contentsOf: paths.fileURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return PracticeProgressDocument()
        } catch {
            throw PracticeProgressRepositoryError.unavailable(
                description: Self.safeDescription(error)
            )
        }

        do {
            return try decodedDocument(from: data)
        } catch {
            throw PracticeProgressRepositoryError.corrupted(
                description: Self.safeDescription(error)
            )
        }
    }

    private func decodedDocument(from data: Data) throws -> PracticeProgressDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PracticeProgressDocument.self, from: data)
    }

    private func saveDocument(_ document: PracticeProgressDocument) throws {
        do {
            try fileManager.createDirectory(at: paths.rootDirectoryURL, withIntermediateDirectories: true)
            try encodedDocument(document).write(to: paths.fileURL, options: .atomic)
        } catch let error as PracticeProgressRepositoryError {
            throw error
        } catch {
            throw PracticeProgressRepositoryError.unavailable(
                description: Self.safeDescription(error)
            )
        }
    }

    private func encodedDocument(_ document: PracticeProgressDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }

    private static func sortedMetadata(
        _ metadata: [SongScorePracticeMetadata]
    ) -> [SongScorePracticeMetadata] {
        metadata.sorted { lhs, rhs in
            if lhs.songID != rhs.songID {
                return lhs.songID.uuidString < rhs.songID.uuidString
            }
            if lhs.scoreFileVersionID != rhs.scoreFileVersionID {
                switch (lhs.scoreFileVersionID, rhs.scoreFileVersionID) {
                case (nil, .some): return true
                case (.some, nil): return false
                case let (.some(lhsToken), .some(rhsToken)):
                    return lhsToken.uuidString < rhsToken.uuidString
                case (nil, nil): break
                }
            }
            if lhs.scoreRevision != rhs.scoreRevision {
                return lhs.scoreRevision < rhs.scoreRevision
            }
            if lhs.preparedAt != rhs.preparedAt {
                return lhs.preparedAt < rhs.preparedAt
            }
            return lhs.totalSourceMeasureCount < rhs.totalSourceMeasureCount
        }
    }

    private static func safeDescription(_ error: Error) -> String {
        let error = error as NSError
        return "\(error.domain)#\(error.code)"
    }
}
