import Diagnostics
import Foundation
import Testing
import ZIPFoundation

@MainActor
struct MacDiagnosticsViewModelTests {
    @Test func exportAndClearUseOnlyItsInjectedStore() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "MacDiagnosticsViewModelTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let store = FileDiagnosticsStore(paths: DiagnosticsPaths(rootDirectoryURL: root))
        let reporter = AppDiagnosticsReporter(exportStore: store)
        _ = await reporter.record(DiagnosticEvent(
            severity: .warning,
            code: .diagnosticsExportFailed,
            category: .diagnostics,
            stage: "test",
            summary: "可导出摘要",
            reason: "safe-reason",
            persistence: .exportable
        ))
        _ = await reporter.record(DiagnosticEvent(
            severity: .error,
            code: .practicePreparationFailed,
            category: .practicePreparation,
            stage: "test",
            summary: "<score-partwise>private score</score-partwise>",
            reason: "path=/Users/example/private.musicxml MIDI1InputEvent(note: 60)",
            persistence: .exportable
        ))

        let viewModel = DiagnosticsViewModel(
            store: store,
            exporter: DiagnosticsArchiveExporter(store: store)
        )
        await viewModel.reload()
        #expect(viewModel.summary.eventCount == 2)
        #expect(await viewModel.prepareExport())

        let archive = try #require(viewModel.pendingArchive)
        let archiveURL = root.appending(path: "diagnostics.zip")
        try archive.data.write(to: archiveURL)
        let zip = try Archive(url: archiveURL, accessMode: .read)
        #expect(Set(zip.map(\.path)) == Set(["diagnostics.jsonl", "diagnostics.txt", "environment.txt"]))
        let jsonl = try extract(path: "diagnostics.jsonl", from: zip)
        let text = try extract(path: "diagnostics.txt", from: zip)
        let exported = try #require(String(data: jsonl + text, encoding: .utf8))
        #expect(exported.contains("/Users/example") == false)
        #expect(exported.contains("<score-partwise>") == false)
        #expect(exported.contains("MIDI1InputEvent") == false)
        #expect(exported.contains("[redacted]"))

        await viewModel.clearLogs()
        #expect(viewModel.summary == .empty)
    }
}

private func extract(path: String, from archive: Archive) throws -> Data {
    let entry = try #require(archive[path])
    var data = Data()
    _ = try archive.extract(entry) { data.append($0) }
    return data
}
