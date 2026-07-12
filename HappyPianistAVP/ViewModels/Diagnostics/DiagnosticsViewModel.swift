import Foundation
import Observation

@MainActor
@Observable
final class DiagnosticsViewModel {
    private let store: any DiagnosticsStoreProtocol
    private let exporter: any DiagnosticsArchiveExporting
    private let now: @Sendable () -> Date

    var summary: DiagnosticLogSummary = .empty
    var pendingArchive: DiagnosticArchive?
    var isLoading = false
    var isExporting = false
    var errorMessage: String?

    init(
        store: any DiagnosticsStoreProtocol,
        exporter: any DiagnosticsArchiveExporting,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.store = store
        self.exporter = exporter
        self.now = now
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            summary = try await store.summary(referenceDate: now())
        } catch {
            errorMessage = "无法读取诊断日志：\(error.localizedDescription)"
        }
    }

    func prepareExport() async -> Bool {
        isExporting = true
        pendingArchive = nil
        defer { isExporting = false }
        do {
            pendingArchive = try await exporter.makeArchive(referenceDate: now())
            return true
        } catch {
            errorMessage = "导出诊断日志失败：\(error.localizedDescription)"
            return false
        }
    }

    func clearLogs() async {
        do {
            try await store.clear()
            pendingArchive = nil
            await reload()
        } catch {
            errorMessage = "清除诊断日志失败：\(error.localizedDescription)"
        }
    }

    func finishExport(_ result: Result<URL, Error>) {
        pendingArchive = nil
        guard case let .failure(error) = result,
              (error as? CocoaError)?.code != .userCancelled
        else {
            return
        }
        errorMessage = "保存诊断日志失败：\(error.localizedDescription)"
    }

    func dismissError() {
        errorMessage = nil
    }
}
