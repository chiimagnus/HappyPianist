import Foundation
import os

public struct DiagnosticRecordResult: Equatable, Sendable {
    public let persistedForExport: Bool

    public init(persistedForExport: Bool) {
        self.persistedForExport = persistedForExport
    }
}

public protocol DiagnosticsReporting: Sendable {
    func recordSystem(_ event: DiagnosticEvent)

    @discardableResult
    func record(_ event: DiagnosticEvent) async -> DiagnosticRecordResult
}

public extension DiagnosticsReporting {
    func recordSystem(_ event: DiagnosticEvent) {
        Task { _ = await record(event) }
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

public protocol SystemDiagnosticsSinkProtocol: Sendable {
    func record(_ event: DiagnosticEvent)
}

public struct OSLogDiagnosticsSink: SystemDiagnosticsSinkProtocol {
    private let subsystem: String

    public init(subsystem: String = Bundle.main.bundleIdentifier ?? "HappyPianist") {
        self.subsystem = subsystem
    }

    public func record(_ event: DiagnosticEvent) {
        let logger = Logger(subsystem: subsystem, category: event.category.rawValue)
        switch event.severity {
        case .debug:
            logger.debug("[\(event.code.rawValue, privacy: .public)] \(event.summary, privacy: .public) | stage=\(event.stage, privacy: .public) | reason=\(event.reason, privacy: .private(mask: .hash))")
        case .info:
            logger.info("[\(event.code.rawValue, privacy: .public)] \(event.summary, privacy: .public) | stage=\(event.stage, privacy: .public) | reason=\(event.reason, privacy: .private(mask: .hash))")
        case .warning:
            logger.warning("[\(event.code.rawValue, privacy: .public)] \(event.summary, privacy: .public) | stage=\(event.stage, privacy: .public) | reason=\(event.reason, privacy: .private(mask: .hash))")
        case .error:
            logger.error("[\(event.code.rawValue, privacy: .public)] \(event.summary, privacy: .public) | stage=\(event.stage, privacy: .public) | reason=\(event.reason, privacy: .private(mask: .hash))")
        }
    }
}

public actor AppDiagnosticsReporter: DiagnosticsReporting {
    private let systemSink: any SystemDiagnosticsSinkProtocol
    private let exportStore: any DiagnosticsStoreProtocol

    public init(
        systemSink: any SystemDiagnosticsSinkProtocol = OSLogDiagnosticsSink(),
        exportStore: any DiagnosticsStoreProtocol
    ) {
        self.systemSink = systemSink
        self.exportStore = exportStore
    }

    public nonisolated func recordSystem(_ event: DiagnosticEvent) {
        systemSink.record(event)
    }

    public func record(_ event: DiagnosticEvent) async -> DiagnosticRecordResult {
        systemSink.record(event)
        guard event.persistence == .exportable else {
            return DiagnosticRecordResult(persistedForExport: false)
        }
        do {
            try await exportStore.append(event.redactedForExport())
            return DiagnosticRecordResult(persistedForExport: true)
        } catch {
            systemSink.record(
                DiagnosticEvent(
                    severity: .error,
                    code: .diagnosticsStoreWriteFailed,
                    category: .diagnostics,
                    stage: "append",
                    summary: "无法写入可导出的诊断日志",
                    reason: String(describing: error),
                    persistence: .systemOnly
                )
            )
            return DiagnosticRecordResult(persistedForExport: false)
        }
    }
}
