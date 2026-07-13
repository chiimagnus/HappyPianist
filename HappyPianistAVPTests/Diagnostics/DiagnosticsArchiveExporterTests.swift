import Foundation
@testable import HappyPianistAVP
import Testing
import ZIPFoundation

private struct FixedDiagnosticsEnvironmentProvider: DiagnosticsEnvironmentProviding {
    func environment() -> DiagnosticsEnvironment {
        DiagnosticsEnvironment(appVersion: "1.2.3", buildNumber: "45", systemVersion: "visionOS test")
    }
}

@Test
func diagnosticsExporterContainsOnlyExpectedEntries() async throws {
    let store = RecordingExportStore(events: [
        DiagnosticEvent(
            timestamp: Date(timeIntervalSince1970: 1_720_742_400),
            severity: .error,
            code: .practiceXMLParseFailed,
            category: .practicePreparation,
            stage: "musicXMLParsing",
            summary: "无法解析 MusicXML",
            reason: "invalid XML",
            persistence: .exportable
        ),
    ])
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
    let exporter = DiagnosticsArchiveExporter(
        store: store,
        environmentProvider: FixedDiagnosticsEnvironmentProvider(),
        calendar: calendar
    )

    let result = try await exporter.makeArchive(referenceDate: Date(timeIntervalSince1970: 1_720_742_400))
    let zipURL = FileManager.default.temporaryDirectory.appending(path: "DiagnosticsArchiveExporterTests-\(UUID().uuidString).zip")
    defer { try? FileManager.default.removeItem(at: zipURL) }
    try result.data.write(to: zipURL)
    let archive = try Archive(url: zipURL, accessMode: .read)

    #expect(Set(archive.map(\.path)) == Set(["diagnostics.jsonl", "diagnostics.txt", "environment.txt"]))
    #expect(result.eventCount == 1)
    #expect(result.fileName == "HappyPianist-Diagnostics-20240712-000000.zip")

    let environment = try extract(path: "environment.txt", from: archive)
    let environmentText = try #require(String(data: environment, encoding: .utf8))
    #expect(environmentText.contains("appVersion: 1.2.3"))
    #expect(environmentText.contains("eventCount: 1"))
    #expect(environmentText.contains("MusicXML") == false)
}

private actor RecordingExportStore: DiagnosticsStoreProtocol {
    let events: [DiagnosticEvent]

    init(events: [DiagnosticEvent]) {
        self.events = events
    }

    func append(_: DiagnosticEvent) {}
    func cleanupExpiredLogs(referenceDate _: Date) {}
    func loadEventsForExport(referenceDate _: Date) -> [DiagnosticEvent] { events }
    func summary(referenceDate _: Date) -> DiagnosticLogSummary { .empty }
    func clear() {}
}

private func extract(path: String, from archive: Archive) throws -> Data {
    let entry = try #require(archive[path])
    var data = Data()
    _ = try archive.extract(entry) { data.append($0) }
    return data
}
