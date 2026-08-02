import Diagnostics
@testable import HappyPianistAVP

actor InMemoryDiagnosticsReporter: DiagnosticsReporting {
    private(set) var events: [DiagnosticEvent] = []
    private let persistResult: Bool

    init(persistResult: Bool = true) {
        self.persistResult = persistResult
    }

    func record(_ event: DiagnosticEvent) -> DiagnosticRecordResult {
        events.append(event)
        return DiagnosticRecordResult(
            persistedForExport: event.persistence == .exportable && persistResult
        )
    }
}
