import Foundation
@testable import HappyPianistAVP
import Testing

@Test
func diagnosticsStoreRetainsSevenCalendarDays() async throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "DiagnosticsStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
    let current = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 12, hour: 12)))
    let store = FileDiagnosticsStore(
        paths: DiagnosticsPaths(rootDirectoryURL: root),
        calendar: calendar,
        now: { current }
    )

    for offset in -8 ... 0 {
        let date = try #require(calendar.date(byAdding: .day, value: offset, to: current))
        try await store.append(testDiagnosticEvent(at: date))
    }

    let events = try await store.loadEventsForExport(referenceDate: current)
    #expect(events.count == 7)
    let cutoff = try #require(calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: current)))
    #expect(events.allSatisfy { $0.timestamp >= cutoff })
}

@Test
func diagnosticsStoreIgnoresCorruptedLinesAndReportsSummary() async throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "DiagnosticsStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
    let current = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 12, hour: 12)))
    let store = FileDiagnosticsStore(
        paths: DiagnosticsPaths(rootDirectoryURL: root),
        calendar: calendar,
        now: { current }
    )

    try await store.append(testDiagnosticEvent(at: current))
    let fileURL = root.appending(path: "diagnostics-2026-07-12.jsonl")
    let handle = try FileHandle(forWritingTo: fileURL)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data("not-json\n".utf8))
    try handle.close()

    let events = try await store.loadEventsForExport(referenceDate: current)
    let summary = try await store.summary(referenceDate: current)
    #expect(events.count == 1)
    #expect(summary.eventCount == 1)
    #expect(summary.totalBytes > 0)
    #expect(summary.coverageStart == current)
    #expect(summary.coverageEnd == current)
}

@Test
func diagnosticsStoreClearRemovesDailyFiles() async throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "DiagnosticsStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let current = Date(timeIntervalSince1970: 1_720_742_400)
    let store = FileDiagnosticsStore(
        paths: DiagnosticsPaths(rootDirectoryURL: root),
        now: { current }
    )

    try await store.append(testDiagnosticEvent(at: current))
    try await store.clear()

    let summary = try await store.summary(referenceDate: current)
    #expect(summary == .empty)
}

private func testDiagnosticEvent(at date: Date) -> DiagnosticEvent {
    DiagnosticEvent(
        timestamp: date,
        severity: .error,
        code: .practicePreparationFailed,
        category: .practicePreparation,
        stage: "test",
        summary: "test",
        reason: "test",
        persistence: .exportable
    )
}
