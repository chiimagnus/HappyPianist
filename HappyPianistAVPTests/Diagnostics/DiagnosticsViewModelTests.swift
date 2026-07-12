import Foundation
@testable import HappyPianistAVP
import Testing

private actor DiagnosticsViewModelStore: DiagnosticsStoreProtocol {
    var storedSummary = DiagnosticLogSummary(
        eventCount: 2,
        totalBytes: 128,
        coverageStart: Date(timeIntervalSince1970: 10),
        coverageEnd: Date(timeIntervalSince1970: 20)
    )
    var didClear = false

    func append(_: DiagnosticEvent) {}
    func cleanupExpiredLogs(referenceDate _: Date) {}
    func loadEventsForExport(referenceDate _: Date) -> [DiagnosticEvent] { [] }
    func summary(referenceDate _: Date) -> DiagnosticLogSummary { storedSummary }
    func clear() {
        didClear = true
        storedSummary = .empty
    }
}

private actor DiagnosticsViewModelExporter: DiagnosticsArchiveExporting {
    let result: Result<DiagnosticArchive, Error>

    init(result: Result<DiagnosticArchive, Error>) {
        self.result = result
    }

    func makeArchive(referenceDate _: Date) throws -> DiagnosticArchive {
        try result.get()
    }
}

private enum DiagnosticsViewModelTestError: Error {
    case exportFailed
}

@Test
@MainActor
func diagnosticsViewModelLoadsExportsAndClears() async {
    let store = DiagnosticsViewModelStore()
    let exporter = DiagnosticsViewModelExporter(result: .success(
        DiagnosticArchive(data: Data([1, 2, 3]), fileName: "logs.zip", eventCount: 2)
    ))
    let viewModel = DiagnosticsViewModel(
        store: store,
        exporter: exporter,
        now: { Date(timeIntervalSince1970: 20) }
    )

    await viewModel.reload()
    #expect(viewModel.summary.eventCount == 2)

    #expect(await viewModel.prepareExport())
    #expect(viewModel.pendingArchive?.fileName == "logs.zip")
    viewModel.finishExport(.success(URL(fileURLWithPath: "/tmp/logs.zip")))
    #expect(viewModel.pendingArchive == nil)

    await viewModel.clearLogs()
    #expect(viewModel.summary == .empty)
    #expect(await store.didClear)
}


@Test
@MainActor
func diagnosticsViewModelReportsSystemExportFailure() async {
    let store = DiagnosticsViewModelStore()
    let exporter = DiagnosticsViewModelExporter(result: .success(
        DiagnosticArchive(data: Data([1]), fileName: "logs.zip", eventCount: 1)
    ))
    let viewModel = DiagnosticsViewModel(store: store, exporter: exporter)

    #expect(await viewModel.prepareExport())
    viewModel.finishExport(.failure(DiagnosticsViewModelTestError.exportFailed))

    #expect(viewModel.pendingArchive == nil)
    #expect(viewModel.errorMessage?.hasPrefix("保存诊断日志失败：") == true)
}

@Test
@MainActor
func diagnosticsViewModelIgnoresCancelledSystemExport() async {
    let store = DiagnosticsViewModelStore()
    let exporter = DiagnosticsViewModelExporter(result: .success(
        DiagnosticArchive(data: Data([1]), fileName: "logs.zip", eventCount: 1)
    ))
    let viewModel = DiagnosticsViewModel(store: store, exporter: exporter)

    #expect(await viewModel.prepareExport())
    viewModel.finishExport(.failure(CocoaError(.userCancelled)))

    #expect(viewModel.pendingArchive == nil)
    #expect(viewModel.errorMessage == nil)
}
