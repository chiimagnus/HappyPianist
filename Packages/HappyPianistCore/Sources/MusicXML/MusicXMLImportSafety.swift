import Foundation
import ZIPFoundation

public struct MusicXMLImportSafetyPolicy: Equatable, Sendable {
    public let maximumRawFileBytes: Int64
    public let maximumArchiveEntryCount: Int
    public let maximumEntryUncompressedBytes: Int64
    public let maximumTotalUncompressedBytes: Int64
    public let maximumCompressionRatio: Double

    public init(
        maximumRawFileBytes: Int64 = 64 * 1024 * 1024,
        maximumArchiveEntryCount: Int = 128,
        maximumEntryUncompressedBytes: Int64 = 32 * 1024 * 1024,
        maximumTotalUncompressedBytes: Int64 = 64 * 1024 * 1024,
        maximumCompressionRatio: Double = 100
    ) {
        self.maximumRawFileBytes = max(1, maximumRawFileBytes)
        self.maximumArchiveEntryCount = max(1, maximumArchiveEntryCount)
        self.maximumEntryUncompressedBytes = max(1, maximumEntryUncompressedBytes)
        self.maximumTotalUncompressedBytes = max(1, maximumTotalUncompressedBytes)
        self.maximumCompressionRatio = max(1, maximumCompressionRatio)
    }
}

public enum MusicXMLImportSafetyRejection: String, Error, Equatable, Sendable {
    case sourceIsNotRegularFile
    case sourceFileTooLarge
    case archiveHasTooManyEntries
    case archiveEntryIsTooLarge
    case archiveTotalIsTooLarge
    case archiveCompressionRatioIsTooHigh
    case archiveEntryNameIsUnsafe
}

/// Validates an import candidate before a host persists it. Parsing repeats
/// the same checks before extraction, so neither boundary can be bypassed.
public func validateMusicXMLImportCandidate(
    at fileURL: URL,
    safetyPolicy: MusicXMLImportSafetyPolicy = .init()
) throws {
    let validator = MusicXMLImportSafetyValidator(policy: safetyPolicy)
    try validator.validateRegularFile(at: fileURL)
    guard fileURL.pathExtension.localizedLowercase == "mxl" else { return }

    let archive: Archive
    do {
        archive = try Archive(url: fileURL, accessMode: .read)
    } catch {
        throw MXLReaderError.invalidArchive
    }
    do {
        try validator.validateArchive(archive)
    } catch let rejection as MusicXMLImportSafetyRejection {
        throw MXLReaderError.rejectedBySafetyPolicy(rejection)
    }
}

enum MusicXMLImportErrorDetails {
    static func safeParserErrorSummary(_: Error) -> String {
        "XMLParser reported a parse error."
    }
}

struct MusicXMLImportSafetyValidator {
    let policy: MusicXMLImportSafetyPolicy

    func readRegularFile(at url: URL) throws -> Data {
        try validateRegularFile(at: url)
        return try Data(contentsOf: url)
    }

    func validateRegularFile(at url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw MusicXMLImportSafetyRejection.sourceIsNotRegularFile
        }
        guard Int64(values.fileSize ?? 0) <= policy.maximumRawFileBytes else {
            throw MusicXMLImportSafetyRejection.sourceFileTooLarge
        }
    }

    func validateArchive(_ archive: Archive) throws {
        var entryCount = 0
        var totalUncompressedBytes: Int64 = 0
        for entry in archive {
            entryCount += 1
            guard entryCount <= policy.maximumArchiveEntryCount else {
                throw MusicXMLImportSafetyRejection.archiveHasTooManyEntries
            }
            _ = try normalizedArchivePath(entry.path)
            let uncompressedBytes = try boundedInt64(entry.uncompressedSize)
            let compressedBytes = try boundedInt64(entry.compressedSize)
            guard uncompressedBytes <= policy.maximumEntryUncompressedBytes else {
                throw MusicXMLImportSafetyRejection.archiveEntryIsTooLarge
            }
            totalUncompressedBytes += uncompressedBytes
            guard totalUncompressedBytes <= policy.maximumTotalUncompressedBytes else {
                throw MusicXMLImportSafetyRejection.archiveTotalIsTooLarge
            }
            let denominator = max(1, compressedBytes)
            guard Double(uncompressedBytes) / Double(denominator) <= policy.maximumCompressionRatio else {
                throw MusicXMLImportSafetyRejection.archiveCompressionRatioIsTooHigh
            }
        }
    }

    func validateExtractableEntry(_ entry: Entry) throws {
        _ = try normalizedArchivePath(entry.path)
        let uncompressedBytes = try boundedInt64(entry.uncompressedSize)
        let compressedBytes = try boundedInt64(entry.compressedSize)
        guard uncompressedBytes <= policy.maximumEntryUncompressedBytes else {
            throw MusicXMLImportSafetyRejection.archiveEntryIsTooLarge
        }
        guard Double(uncompressedBytes) / Double(max(1, compressedBytes)) <= policy.maximumCompressionRatio else {
            throw MusicXMLImportSafetyRejection.archiveCompressionRatioIsTooHigh
        }
    }

    func normalizedArchivePath(_ rawPath: String) throws -> String {
        let normalized = rawPath.replacing("\\", with: "/")
        let isDirectory = normalized.hasSuffix("/")
        let path = isDirectory ? String(normalized.dropLast()) : normalized
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard path.isEmpty == false,
              path.hasPrefix("/") == false,
              path.contains(":") == false,
              components.isEmpty == false,
              components.allSatisfy({ $0.isEmpty == false && $0 != "." && $0 != ".." }),
              path.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F })
        else {
            throw MusicXMLImportSafetyRejection.archiveEntryNameIsUnsafe
        }
        return components.joined(separator: "/") + (isDirectory ? "/" : "")
    }

    private func boundedInt64(_ value: UInt64) throws -> Int64 {
        guard value <= UInt64(Int64.max) else {
            throw MusicXMLImportSafetyRejection.archiveEntryIsTooLarge
        }
        return Int64(value)
    }
}
