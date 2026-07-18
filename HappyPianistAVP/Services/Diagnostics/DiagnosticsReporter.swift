import Foundation
import os

struct DiagnosticRecordResult: Equatable {
    let persistedForExport: Bool
}

protocol DiagnosticsReporting: Sendable {
    func recordSystem(_ event: DiagnosticEvent)

    @discardableResult
    func record(_ event: DiagnosticEvent) async -> DiagnosticRecordResult
}

extension DiagnosticsReporting {
    func recordSystem(_ event: DiagnosticEvent) {
        Task { _ = await record(event) }
    }


    func recordPianoPerformance(_ sample: PianoPerformanceDiagnosticSample) {
        recordSystem(sample.diagnosticEvent)
    }

    func recordSystem(
        severity: DiagnosticSeverity,
        category: DiagnosticCategory,
        stage: String,
        summary: String,
        reason: String
    ) {
        recordSystem(
            DiagnosticEvent(
                severity: severity,
                code: .runtimeEvent,
                category: category,
                stage: stage,
                summary: summary,
                reason: reason,
                persistence: .systemOnly
            )
        )
    }
}

protocol SystemDiagnosticsSinkProtocol: Sendable {
    func record(_ event: DiagnosticEvent)
}

struct OSLogDiagnosticsSink: SystemDiagnosticsSinkProtocol {
    private let subsystem: String

    init(subsystem: String = Bundle.main.bundleIdentifier ?? "HappyPianistAVP") {
        self.subsystem = subsystem
    }

    func record(_ event: DiagnosticEvent) {
        let logger = Logger(subsystem: subsystem, category: event.category.rawValue)
        switch event.severity {
        case .debug:
            logger.debug(
                "[\(event.code.rawValue, privacy: .public)] \(event.summary, privacy: .public) | stage=\(event.stage, privacy: .public) | reason=\(event.reason, privacy: .private(mask: .hash))"
            )
        case .info:
            logger.info(
                "[\(event.code.rawValue, privacy: .public)] \(event.summary, privacy: .public) | stage=\(event.stage, privacy: .public) | reason=\(event.reason, privacy: .private(mask: .hash))"
            )
        case .warning:
            logger.warning(
                "[\(event.code.rawValue, privacy: .public)] \(event.summary, privacy: .public) | stage=\(event.stage, privacy: .public) | reason=\(event.reason, privacy: .private(mask: .hash))"
            )
        case .error:
            logger.error(
                "[\(event.code.rawValue, privacy: .public)] \(event.summary, privacy: .public) | stage=\(event.stage, privacy: .public) | reason=\(event.reason, privacy: .private(mask: .hash))"
            )
        }
    }
}

actor AppDiagnosticsReporter: DiagnosticsReporting {
    private let systemSink: any SystemDiagnosticsSinkProtocol
    private let exportStore: any DiagnosticsStoreProtocol

    init(
        systemSink: any SystemDiagnosticsSinkProtocol = OSLogDiagnosticsSink(),
        exportStore: any DiagnosticsStoreProtocol
    ) {
        self.systemSink = systemSink
        self.exportStore = exportStore
    }

    nonisolated func recordSystem(_ event: DiagnosticEvent) {
        systemSink.record(event)
    }

    func record(_ event: DiagnosticEvent) async -> DiagnosticRecordResult {
        systemSink.record(event)
        guard event.persistence == .exportable else {
            return DiagnosticRecordResult(persistedForExport: false)
        }
        do {
            try await exportStore.append(event)
            return DiagnosticRecordResult(persistedForExport: true)
        } catch {
            let fallback = DiagnosticEvent(
                severity: .error,
                code: .diagnosticsStoreWriteFailed,
                category: .diagnostics,
                stage: "append",
                summary: "无法写入可导出的诊断日志",
                reason: String(describing: error),
                persistence: .systemOnly
            )
            systemSink.record(fallback)
            return DiagnosticRecordResult(persistedForExport: false)
        }
    }
}
