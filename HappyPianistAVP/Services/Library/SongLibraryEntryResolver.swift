import Foundation

struct ResolvedSongLibraryEntry: Equatable {
    let entry: SongLibraryEntry
    let scoreURL: URL
    let diagnosticFileReference: DiagnosticFileReference?
}

struct SongLibraryEntryResolutionError: Error, Equatable {
    let preparationError: PracticePreparationError
    let diagnosticFileReference: DiagnosticFileReference?
}

protocol SongLibraryEntryResolving: Sendable {
    func resolve(songID: UUID) async throws -> ResolvedSongLibraryEntry
}

actor SongLibraryEntryResolver: SongLibraryEntryResolving {
    private let indexStore: any SongLibraryIndexStoreProtocol
    private let bundledProvider: any BundledSongLibraryProviderProtocol
    private let fileStore: any SongFileStoreProtocol
    private let fileManager: FileManager

    init(
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

    func resolve(songID: UUID) async throws -> ResolvedSongLibraryEntry {
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
