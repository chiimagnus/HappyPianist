import Foundation
@testable import Diagnostics
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
        DiagnosticEvent(timestamp: Date(timeIntervalSince1970: 1_720_742_400), severity: .error, code: .practiceXMLParseFailed, category: .practicePreparation, stage: "musicXMLParsing", summary: "无法解析 MusicXML", reason: "invalid XML", persistence: .exportable),
    ])
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
    let result = try await DiagnosticsArchiveExporter(store: store, environmentProvider: FixedDiagnosticsEnvironmentProvider(), calendar: calendar)
        .makeArchive(referenceDate: Date(timeIntervalSince1970: 1_720_742_400))
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

@Test
func diagnosticsExporterRedactsUnsafeCustomStoreEvents() async throws {
    let store = RecordingExportStore(events: [
        DiagnosticEvent(
            timestamp: Date(timeIntervalSince1970: 1_720_742_400),
            severity: .error,
            code: .practiceXMLParseFailed,
            category: .practicePreparation,
            stage: "test",
            summary: "<note>private score</note>",
            reason: "path=/Users/example/private.musicxml MIDI1InputEvent(note: 60)",
            persistence: .exportable
        ),
    ])
    let result = try await DiagnosticsArchiveExporter(store: store)
        .makeArchive(referenceDate: Date(timeIntervalSince1970: 1_720_742_400))
    let zipURL = FileManager.default.temporaryDirectory.appending(path: "DiagnosticsArchiveExporterTests-\(UUID().uuidString).zip")
    defer { try? FileManager.default.removeItem(at: zipURL) }
    try result.data.write(to: zipURL)
    let archive = try Archive(url: zipURL, accessMode: .read)
    let jsonl = try extract(path: "diagnostics.jsonl", from: archive)
    let text = try extract(path: "diagnostics.txt", from: archive)
    let exported = try #require(String(data: jsonl + text, encoding: .utf8))

    #expect(exported.contains("/Users/example") == false)
    #expect(exported.contains("<note>") == false)
    #expect(exported.contains("MIDI1InputEvent") == false)
    #expect(exported.contains("[redacted]"))
}

private actor RecordingExportStore: DiagnosticsStoreProtocol {
    let events: [DiagnosticEvent]
    init(events: [DiagnosticEvent]) { self.events = events }
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
