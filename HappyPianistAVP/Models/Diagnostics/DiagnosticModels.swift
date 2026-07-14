import Foundation

enum DiagnosticSeverity: String, Codable, CaseIterable, Sendable {
    case debug
    case info
    case warning
    case error
}

enum DiagnosticCategory: String, Codable, CaseIterable, Sendable {
    case general
    case library
    case practicePreparation
    case practiceSession
    case persistence
    case audio
    case midi
    case immersiveSpace
    case ai
    case diagnostics
}

enum DiagnosticPersistence: String, Codable, Sendable {
    case systemOnly
    case exportable
}

enum DiagnosticCode: String, Codable, CaseIterable, Sendable {
    case practicePreparationStarted = "PRACTICE_PREPARATION_STARTED"
    case practicePreparationSucceeded = "PRACTICE_PREPARATION_SUCCEEDED"
    case practiceScoreFileNotFound = "PRACTICE_SCORE_FILE_NOT_FOUND"
    case practiceScoreFileUnreadable = "PRACTICE_SCORE_FILE_UNREADABLE"
    case practiceMXLInvalidArchive = "PRACTICE_MXL_INVALID_ARCHIVE"
    case practiceMXLMissingContainer = "PRACTICE_MXL_MISSING_CONTAINER"
    case practiceMXLMissingRootfile = "PRACTICE_MXL_MISSING_ROOTFILE"
    case practiceMXLMissingScore = "PRACTICE_MXL_MISSING_SCORE"
    case practiceMXLInvalidContainer = "PRACTICE_MXL_INVALID_CONTAINER"
    case practiceXMLParseFailed = "PRACTICE_XML_PARSE_FAILED"
    case practiceNoPlayableNotes = "PRACTICE_NO_PLAYABLE_NOTES"
    case practiceMissingMeasureStructure = "PRACTICE_MISSING_MEASURE_STRUCTURE"
    case practicePreparationFailed = "PRACTICE_PREPARATION_FAILED"
    case practiceSavedConfigurationRepaired = "PRACTICE_SAVED_CONFIGURATION_REPAIRED"
    case diagnosticsStoreWriteFailed = "DIAGNOSTICS_STORE_WRITE_FAILED"
    case diagnosticsRetentionCleanupFailed = "DIAGNOSTICS_RETENTION_CLEANUP_FAILED"
    case diagnosticsExportFailed = "DIAGNOSTICS_EXPORT_FAILED"
    case diagnosticsCleared = "DIAGNOSTICS_CLEARED"
}

struct DiagnosticFileReference: Codable, Equatable, Sendable {
    let fileName: String
    let relativePath: String

    init?(fileName: String, relativePath: String) {
        let normalizedFileName = URL(fileURLWithPath: fileName).lastPathComponent
        let normalizedPath = relativePath.replacing("\\", with: "/")
        let components = normalizedPath.split(separator: "/", omittingEmptySubsequences: true)
        guard normalizedFileName.isEmpty == false,
              normalizedPath.hasPrefix("/") == false,
              normalizedPath.contains("://") == false,
              components.allSatisfy({ $0 != "." && $0 != ".." })
        else {
            return nil
        }
        self.fileName = normalizedFileName
        self.relativePath = components.joined(separator: "/")
    }
}

struct DiagnosticSourceLocation: Codable, Equatable, Sendable {
    let line: Int?
    let column: Int?
    let measure: String?

    init(line: Int? = nil, column: Int? = nil, measure: String? = nil) {
        self.line = line.flatMap { $0 > 0 ? $0 : nil }
        self.column = column.flatMap { $0 > 0 ? $0 : nil }
        self.measure = measure?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

struct DiagnosticEvent: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let timestamp: Date
    let severity: DiagnosticSeverity
    let code: DiagnosticCode
    let category: DiagnosticCategory
    let stage: String
    let summary: String
    let reason: String
    let songID: UUID?
    let scoreRevision: String?
    let file: DiagnosticFileReference?
    let sourceLocation: DiagnosticSourceLocation?
    let persistence: DiagnosticPersistence

    init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        severity: DiagnosticSeverity,
        code: DiagnosticCode,
        category: DiagnosticCategory,
        stage: String,
        summary: String,
        reason: String,
        songID: UUID? = nil,
        scoreRevision: String? = nil,
        file: DiagnosticFileReference? = nil,
        sourceLocation: DiagnosticSourceLocation? = nil,
        persistence: DiagnosticPersistence
    ) {
        self.id = id
        self.timestamp = timestamp
        self.severity = severity
        self.code = code
        self.category = category
        self.stage = stage.trimmingCharacters(in: .whitespacesAndNewlines)
        self.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        self.reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        self.songID = songID
        self.scoreRevision = scoreRevision?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.file = file
        self.sourceLocation = sourceLocation
        self.persistence = persistence
    }

    var textRepresentation: String {
        var lines = [
            "timestamp: \(DiagnosticsDateText.iso8601(timestamp))",
            "level: \(severity.rawValue)",
            "code: \(code.rawValue)",
            "category: \(category.rawValue)",
            "stage: \(stage)",
            "summary: \(summary)",
            "reason: \(reason)",
        ]
        if let songID {
            lines.append("songID: \(songID.uuidString)")
        }
        if let scoreRevision {
            lines.append("scoreRevision: \(scoreRevision)")
        }
        if let file {
            lines.append("file: \(file.fileName)")
            lines.append("relativePath: \(file.relativePath)")
        }
        if let measure = sourceLocation?.measure {
            lines.append("measure: \(measure)")
        }
        if let line = sourceLocation?.line {
            lines.append("line: \(line)")
        }
        if let column = sourceLocation?.column {
            lines.append("column: \(column)")
        }
        return lines.joined(separator: "\n")
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

struct DiagnosticLogSummary: Equatable, Sendable {
    let eventCount: Int
    let totalBytes: Int64
    let coverageStart: Date?
    let coverageEnd: Date?

    static let empty = DiagnosticLogSummary(
        eventCount: 0,
        totalBytes: 0,
        coverageStart: nil,
        coverageEnd: nil
    )
}

enum DiagnosticsDateText {
    static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    static func dayToken(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return [
            padded(components.year, width: 4),
            padded(components.month, width: 2),
            padded(components.day, width: 2),
        ].joined(separator: "-")
    }

    static func archiveToken(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        let day = [
            padded(components.year, width: 4),
            padded(components.month, width: 2),
            padded(components.day, width: 2),
        ].joined()
        let time = [
            padded(components.hour, width: 2),
            padded(components.minute, width: 2),
            padded(components.second, width: 2),
        ].joined()
        return "\(day)-\(time)"
    }

    private static func padded(_ component: Int?, width: Int) -> String {
        let text = String(max(0, component ?? 0))
        return String(repeating: "0", count: max(0, width - text.count)) + text
    }
}
