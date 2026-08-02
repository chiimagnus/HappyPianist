import Foundation
@testable import Diagnostics
import os
import Testing

private final class RecordingSystemDiagnosticsSink: SystemDiagnosticsSinkProtocol {
    private let eventsStorage = OSAllocatedUnfairLock(initialState: [DiagnosticEvent]())

    var events: [DiagnosticEvent] { eventsStorage.withLock { $0 } }

    func record(_ event: DiagnosticEvent) {
        eventsStorage.withLock { $0.append(event) }
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
    func loadEventsForExport(referenceDate _: Date) -> [DiagnosticEvent] { events }
    func summary(referenceDate _: Date) -> DiagnosticLogSummary { .empty }
    func clear() { events = [] }
    func setAppendError(_ error: Error?) { appendError = error }
}

@Test
func reporterForwardsExportableEventToBothSinks() async {
    let systemSink = RecordingSystemDiagnosticsSink()
    let store = RecordingDiagnosticsStore()
    let event = testReporterEvent(persistence: .exportable)
    let result = await AppDiagnosticsReporter(systemSink: systemSink, exportStore: store).record(event)
    #expect(result.persistedForExport)
    #expect(systemSink.events == [event])
    #expect(await store.events == [event])
}

@Test
func reporterKeepsSystemOnlyEventOutOfFileStore() async {
    let systemSink = RecordingSystemDiagnosticsSink()
    let store = RecordingDiagnosticsStore()
    let event = testReporterEvent(persistence: .systemOnly)
    let result = await AppDiagnosticsReporter(systemSink: systemSink, exportStore: store).record(event)
    #expect(result.persistedForExport == false)
    #expect(systemSink.events == [event])
    #expect(await store.events.isEmpty)
}

@Test
func reporterRecordsSynchronousSystemEventWithoutTouchingFileStore() async {
    let systemSink = RecordingSystemDiagnosticsSink()
    let store = RecordingDiagnosticsStore()
    let reporter = AppDiagnosticsReporter(systemSink: systemSink, exportStore: store)
    reporter.recordSystem(testReporterEvent(persistence: .systemOnly))
    #expect(systemSink.events.count == 1)
    #expect(await store.events.isEmpty)
}

@Test
func reporterKeepsAppRunningWhenFileStoreFails() async {
    let systemSink = RecordingSystemDiagnosticsSink()
    let store = RecordingDiagnosticsStore()
    await store.setAppendError(CocoaError(.fileWriteOutOfSpace))
    let result = await AppDiagnosticsReporter(systemSink: systemSink, exportStore: store)
        .record(testReporterEvent(persistence: .exportable))
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
