import Diagnostics

extension DiagnosticsReporting {
    @discardableResult
    public func recordOutputMetrics(_ snapshot: PianoOutputMetricsSnapshot) -> Task<DiagnosticRecordResult, Never> {
        Task { await record(snapshot.diagnosticEvent) }
    }
}
