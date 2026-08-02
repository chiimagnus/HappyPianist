import Foundation
import ZIPFoundation

public struct DiagnosticsEnvironment: Equatable, Sendable {
    public let appVersion: String
    public let buildNumber: String
    public let systemVersion: String

    public init(appVersion: String, buildNumber: String, systemVersion: String) {
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.systemVersion = systemVersion
    }
}

public protocol DiagnosticsEnvironmentProviding: Sendable {
    func environment() -> DiagnosticsEnvironment
}

public struct LiveDiagnosticsEnvironmentProvider: DiagnosticsEnvironmentProviding {
    public init() {}

    public func environment() -> DiagnosticsEnvironment {
        DiagnosticsEnvironment(
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            buildNumber: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            systemVersion: ProcessInfo.processInfo.operatingSystemVersionString
        )
    }
}

public struct DiagnosticArchive: Equatable, Sendable {
    public let data: Data
    public let fileName: String
    public let eventCount: Int

    public init(data: Data, fileName: String, eventCount: Int) {
        self.data = data
        self.fileName = fileName
        self.eventCount = eventCount
    }
}

public protocol DiagnosticsArchiveExporting: Sendable {
    func makeArchive(referenceDate: Date) async throws -> DiagnosticArchive
}

public actor DiagnosticsArchiveExporter: DiagnosticsArchiveExporting {
    private let store: any DiagnosticsStoreProtocol
    private let environmentProvider: any DiagnosticsEnvironmentProviding
    private let fileManager: FileManager
    private let calendar: Calendar

    public init(
        store: any DiagnosticsStoreProtocol,
        environmentProvider: any DiagnosticsEnvironmentProviding = LiveDiagnosticsEnvironmentProvider(),
        fileManager: FileManager = .default,
        calendar: Calendar = .current
    ) {
        self.store = store
        self.environmentProvider = environmentProvider
        self.fileManager = fileManager
        self.calendar = calendar
    }

    public func makeArchive(referenceDate: Date = .now) async throws -> DiagnosticArchive {
        let events = try await store.loadEventsForExport(referenceDate: referenceDate)
        let root = fileManager.temporaryDirectory
            .appending(path: "HappyPianist-Diagnostics-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let jsonlURL = root.appending(path: "diagnostics.jsonl")
        let textURL = root.appending(path: "diagnostics.txt")
        let environmentURL = root.appending(path: "environment.txt")
        let archiveURL = root.appending(path: "archive.zip")
        try makeJSONL(events).write(to: jsonlURL, options: .atomic)
        try makeText(events).write(to: textURL, atomically: true, encoding: .utf8)
        try makeEnvironmentText(events: events, generatedAt: referenceDate)
            .write(to: environmentURL, atomically: true, encoding: .utf8)

        let archive = try Archive(url: archiveURL, accessMode: .create)
        try archive.addEntry(with: jsonlURL.lastPathComponent, relativeTo: root, compressionMethod: .deflate)
        try archive.addEntry(with: textURL.lastPathComponent, relativeTo: root, compressionMethod: .deflate)
        try archive.addEntry(with: environmentURL.lastPathComponent, relativeTo: root, compressionMethod: .deflate)
        return try DiagnosticArchive(
            data: Data(contentsOf: archiveURL),
            fileName: "HappyPianist-Diagnostics-\(DiagnosticsDateText.archiveToken(referenceDate, calendar: calendar)).zip",
            eventCount: events.count
        )
    }

    private func makeJSONL(_ events: [DiagnosticEvent]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        var result = Data()
        for event in events {
            try result.append(encoder.encode(event))
            result.append(0x0A)
        }
        return result
    }

    private func makeText(_ events: [DiagnosticEvent]) -> String {
        events.map(\.textRepresentation).joined(separator: "\n\n---\n\n")
    }

    private func makeEnvironmentText(events: [DiagnosticEvent], generatedAt: Date) -> String {
        let environment = environmentProvider.environment()
        let coverageStart = events.map(\.timestamp).min().map(DiagnosticsDateText.iso8601) ?? "none"
        let coverageEnd = events.map(\.timestamp).max().map(DiagnosticsDateText.iso8601) ?? "none"
        return [
            "appVersion: \(environment.appVersion)",
            "buildNumber: \(environment.buildNumber)",
            "systemVersion: \(environment.systemVersion)",
            "generatedAt: \(DiagnosticsDateText.iso8601(generatedAt))",
            "coverageStart: \(coverageStart)",
            "coverageEnd: \(coverageEnd)",
            "eventCount: \(events.count)",
            "retentionDays: 7",
            "privacy: no raw score, audio, MIDI stream, AI conversation, credential, or absolute path data",
        ].joined(separator: "\n")
    }
}
