import Foundation

protocol DiagnosticsStoreProtocol: Sendable {
    func append(_ event: DiagnosticEvent) async throws
    func cleanupExpiredLogs(referenceDate: Date) async throws
    func loadEventsForExport(referenceDate: Date) async throws -> [DiagnosticEvent]
    func summary(referenceDate: Date) async throws -> DiagnosticLogSummary
    func clear() async throws
}

actor FileDiagnosticsStore: DiagnosticsStoreProtocol {
    private let fileManager: FileManager
    private let paths: DiagnosticsPaths
    private let calendar: Calendar
    private let retentionDays: Int
    private let now: @Sendable () -> Date
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var lastCleanupDay: Date?

    init(
        fileManager: FileManager = .default,
        paths: DiagnosticsPaths = DiagnosticsPaths(),
        calendar: Calendar = .current,
        retentionDays: Int = 7,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.fileManager = fileManager
        self.paths = paths
        self.calendar = calendar
        self.retentionDays = max(1, retentionDays)
        self.now = now
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func append(_ event: DiagnosticEvent) throws {
        let referenceDate = now()
        try cleanupIfNeeded(referenceDate: referenceDate)
        try paths.ensureDirectoryExists()
        let fileURL = try dailyFileURL(for: event.timestamp)
        let encoded = try encoder.encode(event)
        var line = encoded
        line.append(0x0A)

        if fileManager.fileExists(atPath: fileURL.path()) {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: fileURL, options: .atomic)
        }
    }

    func cleanupExpiredLogs(referenceDate: Date) throws {
        try paths.ensureDirectoryExists()
        let cutoff = retentionCutoff(referenceDate: referenceDate)
        for url in try diagnosticFileURLs() {
            guard let date = dateFromFileName(url.lastPathComponent) else { continue }
            if date < cutoff {
                try fileManager.removeItem(at: url)
            }
        }
        lastCleanupDay = calendar.startOfDay(for: referenceDate)
    }

    func loadEventsForExport(referenceDate: Date) throws -> [DiagnosticEvent] {
        try cleanupExpiredLogs(referenceDate: referenceDate)
        return try loadEvents()
    }

    func summary(referenceDate: Date) throws -> DiagnosticLogSummary {
        try cleanupExpiredLogs(referenceDate: referenceDate)
        let urls = try diagnosticFileURLs()
        let events = try loadEvents(from: urls)
        let totalBytes = try urls.reduce(Int64(0)) { partial, url in
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            return partial + Int64(values.fileSize ?? 0)
        }
        return DiagnosticLogSummary(
            eventCount: events.count,
            totalBytes: totalBytes,
            coverageStart: events.map(\.timestamp).min(),
            coverageEnd: events.map(\.timestamp).max()
        )
    }

    func clear() throws {
        let root = try paths.rootDirectoryURL()
        guard fileManager.fileExists(atPath: root.path()) else { return }
        for url in try diagnosticFileURLs() {
            try fileManager.removeItem(at: url)
        }
        lastCleanupDay = nil
    }

    private func cleanupIfNeeded(referenceDate: Date) throws {
        let day = calendar.startOfDay(for: referenceDate)
        guard lastCleanupDay != day else { return }
        try cleanupExpiredLogs(referenceDate: referenceDate)
    }

    private func retentionCutoff(referenceDate: Date) -> Date {
        let currentDay = calendar.startOfDay(for: referenceDate)
        return calendar.date(byAdding: .day, value: -(retentionDays - 1), to: currentDay) ?? currentDay
    }

    private func loadEvents() throws -> [DiagnosticEvent] {
        try loadEvents(from: diagnosticFileURLs())
    }

    private func loadEvents(from urls: [URL]) throws -> [DiagnosticEvent] {
        var events: [DiagnosticEvent] = []
        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let data = try Data(contentsOf: url)
            for line in data.split(separator: 0x0A) where line.isEmpty == false {
                guard let event = try? decoder.decode(DiagnosticEvent.self, from: Data(line)) else {
                    continue
                }
                events.append(event)
            }
        }
        return events.sorted { lhs, rhs in
            if lhs.timestamp == rhs.timestamp {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.timestamp < rhs.timestamp
        }
    }

    private func diagnosticFileURLs() throws -> [URL] {
        let root = try paths.rootDirectoryURL()
        guard fileManager.fileExists(atPath: root.path()) else { return [] }
        return try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ).filter { url in
            url.pathExtension == "jsonl" && url.lastPathComponent.hasPrefix("diagnostics-")
        }
    }

    private func dailyFileURL(for date: Date) throws -> URL {
        let token = DiagnosticsDateText.dayToken(date, calendar: calendar)
        return try paths.rootDirectoryURL().appending(path: "diagnostics-\(token).jsonl")
    }

    private func dateFromFileName(_ fileName: String) -> Date? {
        guard fileName.hasPrefix("diagnostics-"), fileName.hasSuffix(".jsonl") else { return nil }
        let token = fileName
            .replacing("diagnostics-", with: "")
            .replacing(".jsonl", with: "")
        let parts = token.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
