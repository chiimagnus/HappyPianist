import Foundation

enum SongLibraryIndexStoreError: LocalizedError, Equatable {
    case corrupted

    var errorDescription: String? {
        switch self {
        case .corrupted:
            "曲库索引已损坏。原文件已保留，请恢复文件后重试。"
        }
    }
}

enum SongLibraryEntryMutationResult: Equatable, Sendable {
    case applied(index: SongLibraryIndex, entry: SongLibraryEntry)
    case notFound(index: SongLibraryIndex)
    case conflict(index: SongLibraryIndex, entry: SongLibraryEntry)

    var index: SongLibraryIndex {
        switch self {
        case let .applied(index, _), let .notFound(index), let .conflict(index, _):
            index
        }
    }
}

protocol SongLibraryIndexStoreProtocol: Actor {
    func load() throws -> SongLibraryIndex
    func setLastSelectedEntryID(_ entryID: UUID?) throws -> SongLibraryIndex
    func appendUserEntry(_ entry: SongLibraryEntry) throws -> SongLibraryIndex
    func removeUserEntry(
        id: UUID,
        fallbackLastSelectedEntryID: UUID?
    ) throws -> SongLibraryEntryMutationResult
    func updateAudioFileName(
        entryID: UUID,
        expectedCurrentFileName: String?,
        newFileName: String?
    ) throws -> SongLibraryEntryMutationResult
}

actor SongLibraryIndexStore: SongLibraryIndexStoreProtocol {
    private let fileManager: FileManager
    private let paths: SongLibraryPaths

    init(fileManager: FileManager = .default, paths: SongLibraryPaths? = nil) {
        self.fileManager = fileManager
        self.paths = paths ?? SongLibraryPaths(fileManager: fileManager)
    }

    func load() throws -> SongLibraryIndex {
        try loadLatest()
    }

    func setLastSelectedEntryID(_ entryID: UUID?) throws -> SongLibraryIndex {
        var index = try loadLatest()
        index.lastSelectedEntryID = entryID
        try write(index)
        return index
    }

    func appendUserEntry(_ entry: SongLibraryEntry) throws -> SongLibraryIndex {
        var index = try loadLatest()
        index.entries.append(entry)
        try write(index)
        return index
    }

    func removeUserEntry(
        id: UUID,
        fallbackLastSelectedEntryID: UUID?
    ) throws -> SongLibraryEntryMutationResult {
        var index = try loadLatest()
        guard let entryIndex = index.entries.firstIndex(where: { $0.id == id }) else {
            return .notFound(index: index)
        }

        let removedEntry = index.entries.remove(at: entryIndex)
        if index.lastSelectedEntryID == id {
            index.lastSelectedEntryID = fallbackLastSelectedEntryID
        }
        try write(index)
        return .applied(index: index, entry: removedEntry)
    }

    func updateAudioFileName(
        entryID: UUID,
        expectedCurrentFileName: String?,
        newFileName: String?
    ) throws -> SongLibraryEntryMutationResult {
        var index = try loadLatest()
        guard let entryIndex = index.entries.firstIndex(where: { $0.id == entryID }) else {
            return .notFound(index: index)
        }
        guard index.entries[entryIndex].audioFileName == expectedCurrentFileName else {
            return .conflict(index: index, entry: index.entries[entryIndex])
        }

        index.entries[entryIndex].audioFileName = newFileName
        let updatedEntry = index.entries[entryIndex]
        try write(index)
        return .applied(index: index, entry: updatedEntry)
    }

    private func loadLatest() throws -> SongLibraryIndex {
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
           text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return .empty
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(SongLibraryIndex.self, from: data)
        } catch {
            throw SongLibraryIndexStoreError.corrupted
        }
    }

    private func write(_ index: SongLibraryIndex) throws {
        try paths.ensureDirectoriesExist()
        let indexFileURL = try paths.indexFileURL()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(index).write(to: indexFileURL, options: .atomic)
    }
}
