import Diagnostics

extension DiagnosticsReporting {
    @discardableResult
    func recordOutputMetrics(_ snapshot: PianoOutputMetricsSnapshot) -> Task<DiagnosticRecordResult, Never> {
        Task { await record(snapshot.diagnosticEvent) }
    }
}
