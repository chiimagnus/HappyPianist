import Foundation
import Diagnostics
import Practice

public struct ResolvedSongLibraryEntry: Equatable, Sendable {
    public let entry: SongLibraryEntry
    public let scoreURL: URL
    public let diagnosticFileReference: DiagnosticFileReference?

    public init(
        entry: SongLibraryEntry,
        scoreURL: URL,
        diagnosticFileReference: DiagnosticFileReference?
    ) {
        self.entry = entry
        self.scoreURL = scoreURL
        self.diagnosticFileReference = diagnosticFileReference
    }
}

public struct SongLibraryEntryResolutionError: Error, Equatable, Sendable {
    public let preparationError: PracticePreparationError
    public let diagnosticFileReference: DiagnosticFileReference?

    public init(
        preparationError: PracticePreparationError,
        diagnosticFileReference: DiagnosticFileReference?
    ) {
        self.preparationError = preparationError
        self.diagnosticFileReference = diagnosticFileReference
    }
}

public protocol SongLibraryEntryResolving: Sendable {
    func resolve(songID: UUID) async throws -> ResolvedSongLibraryEntry
}

public actor SongLibraryEntryResolver: SongLibraryEntryResolving {
    private let indexStore: any SongLibraryIndexStoreProtocol
    private let bundledProvider: any BundledSongLibraryProviderProtocol
    private let fileStore: any SongFileStoreProtocol
    private let fileManager: FileManager

    public init(
        indexStore: any SongLibraryIndexStoreProtocol,
        bundledProvider: any BundledSongLibraryProviderProtocol,
        fileStore: any SongFileStoreProtocol,
        fileManager: FileManager = .default
    ) {
        self.indexStore = indexStore
        self.bundledProvider = bundledProvider
        self.fileStore = fileStore
        self.fileManager = fileManager
    }

    public func resolve(songID: UUID) async throws -> ResolvedSongLibraryEntry {
        if let entry = bundledProvider.bundledEntries().first(where: { $0.id == songID }) {
            let fileReference = diagnosticReference(entry: entry, location: "Bundle")
            guard let scoreURL = bundledProvider.musicXMLURL(fileName: entry.musicXMLFileName) else {
                throw SongLibraryEntryResolutionError(
                    preparationError: .scoreFileNotFound,
                    diagnosticFileReference: fileReference
                )
            }
            do {
                try validateBundledScore(at: scoreURL)
            } catch {
                throw SongLibraryEntryResolutionError(
                    preparationError: (error as? PracticePreparationError) ?? mapFileAccessError(error),
                    diagnosticFileReference: fileReference
                )
            }
            return ResolvedSongLibraryEntry(
                entry: entry,
                scoreURL: scoreURL,
                diagnosticFileReference: fileReference
            )
        }

        let index: SongLibraryIndex
        do {
            index = try await indexStore.load()
        } catch {
            throw SongLibraryEntryResolutionError(
                preparationError: .scoreFileUnreadable(
                    reason: PracticePreparationErrorDetails.safeErrorSummary(error)
                ),
                diagnosticFileReference: nil
            )
        }
        guard let entry = index.entries.first(where: { $0.id == songID }) else {
            throw SongLibraryEntryResolutionError(
                preparationError: .scoreFileNotFound,
                diagnosticFileReference: nil
            )
        }

        let fileReference = diagnosticReference(entry: entry, location: "SongLibrary/scores")
        do {
            let scoreURL = try await fileStore.scoreFileURL(fileName: entry.musicXMLFileName)
            return ResolvedSongLibraryEntry(
                entry: entry,
                scoreURL: scoreURL,
                diagnosticFileReference: fileReference
            )
        } catch {
            throw SongLibraryEntryResolutionError(
                preparationError: mapFileAccessError(error),
                diagnosticFileReference: fileReference
            )
        }
    }

    private func validateBundledScore(at scoreURL: URL) throws {
        do {
            let attributes = try fileManager.attributesOfItem(atPath: scoreURL.path(percentEncoded: false))
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  fileManager.isReadableFile(atPath: scoreURL.path(percentEncoded: false))
            else {
                throw SongFileStoreError.unreadableScoreFile
            }
        } catch {
            throw mapFileAccessError(error)
        }
    }

    private func mapFileAccessError(_ error: Error) -> PracticePreparationError {
        let cocoaError = error as? CocoaError
        if cocoaError?.code == .fileNoSuchFile || cocoaError?.code == .fileReadNoSuchFile {
            return .scoreFileNotFound
        }
        return .scoreFileUnreadable(
            reason: PracticePreparationErrorDetails.safeErrorSummary(error)
        )
    }

    private func diagnosticReference(
        entry: SongLibraryEntry,
        location: String
    ) -> DiagnosticFileReference? {
        let fileName = URL(fileURLWithPath: entry.musicXMLFileName).lastPathComponent
        return DiagnosticFileReference(
            fileName: fileName,
            relativePath: "\(location)/\(fileName)"
        )
    }
}
