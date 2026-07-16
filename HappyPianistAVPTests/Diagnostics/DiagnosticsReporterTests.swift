import Foundation
@testable import HappyPianistAVP
import Testing

private final class RecordingSystemDiagnosticsSink: SystemDiagnosticsSinkProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var storedEvents: [DiagnosticEvent] = []

    var events: [DiagnosticEvent] {
        lock.withLock { storedEvents }
    }

    func record(_ event: DiagnosticEvent) {
        lock.withLock { storedEvents.append(event) }
    }
}

private actor RecordingDiagnosticsStore: DiagnosticsStoreProtocol {
    var events: [DiagnosticEvent] = []
    var appendError: Error?

    func append(_ event: DiagnosticEvent) throws {
        if let appendError { throw appendError }
        events.append(event)
    }

    func cleanupExpiredLogs(referenceDate _: Date) {}
    func loadEventsForExport(referenceDate _: Date) -> [DiagnosticEvent] {
        events
    }

    func summary(referenceDate _: Date) -> DiagnosticLogSummary {
        .empty
    }

    func clear() {
        events = []
    }
}

@Test
func reporterForwardsExportableEventToBothSinks() async {
    let systemSink = RecordingSystemDiagnosticsSink()
    let store = RecordingDiagnosticsStore()
    let reporter = AppDiagnosticsReporter(systemSink: systemSink, exportStore: store)
    let event = testReporterEvent(persistence: .exportable)

    let result = await reporter.record(event)

    #expect(result.persistedForExport)
    #expect(systemSink.events == [event])
    #expect(await store.events == [event])
}

@Test
func reporterKeepsSystemOnlyEventOutOfFileStore() async {
    let systemSink = RecordingSystemDiagnosticsSink()
    let store = RecordingDiagnosticsStore()
    let reporter = AppDiagnosticsReporter(systemSink: systemSink, exportStore: store)
    let event = testReporterEvent(persistence: .systemOnly)

    let result = await reporter.record(event)

    #expect(result.persistedForExport == false)
    #expect(systemSink.events == [event])
    #expect(await store.events.isEmpty)
}

@Test
func reporterRecordsSynchronousSystemEventWithoutTouchingFileStore() async {
    let systemSink = RecordingSystemDiagnosticsSink()
    let store = RecordingDiagnosticsStore()
    let reporter = AppDiagnosticsReporter(systemSink: systemSink, exportStore: store)
    let event = testReporterEvent(persistence: .systemOnly)

    reporter.recordSystem(event)

    #expect(systemSink.events == [event])
    #expect(await store.events.isEmpty)
}

@Test
func reporterKeepsAppRunningWhenFileStoreFails() async {
    let systemSink = RecordingSystemDiagnosticsSink()
    let store = RecordingDiagnosticsStore()
    await store.setAppendError(CocoaError(.fileWriteOutOfSpace))
    let reporter = AppDiagnosticsReporter(systemSink: systemSink, exportStore: store)

    let result = await reporter.record(testReporterEvent(persistence: .exportable))

    #expect(result.persistedForExport == false)
    #expect(systemSink.events.count == 2)
    #expect(systemSink.events.last?.code == .diagnosticsStoreWriteFailed)
}

private func testReporterEvent(persistence: DiagnosticPersistence) -> DiagnosticEvent {
    DiagnosticEvent(
        severity: .error,
        code: .practicePreparationFailed,
        category: .practicePreparation,
        stage: "test",
        summary: "test",
        reason: "test",
        persistence: persistence
    )
}

private extension RecordingDiagnosticsStore {
    func setAppendError(_ error: Error?) {
        appendError = error
    }
}
