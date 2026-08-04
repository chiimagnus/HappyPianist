import Diagnostics
import Foundation

struct PianoPerformancePlanBuildDiagnosticSample: Equatable {
    let songID: UUID
    let scoreRevision: String
    let durationBucket: PianoPerformanceDurationBucket
    let noteEventCount: Int
    let tempoEventCount: Int
    let controllerEventCount: Int
    let annotationCount: Int
    let unsupportedNoteCount: Int
    let approximationCount: Int
    let stepMismatchCount: Int
    let highlightMismatchCount: Int
    let notationMismatchCount: Int

    var diagnosticEvent: DiagnosticEvent {
        DiagnosticEvent(
            severity: outcome == .succeeded ? .info : .warning,
            code: .pianoPerformancePipeline,
            category: .pianoPerformance,
            stage: PianoPerformanceDiagnosticStage.plan.rawValue,
            summary: "钢琴演奏计划构建结果",
            reason: [
                "outcome=\(outcome.rawValue)",
                "duration=\(durationBucket.rawValue)",
                "noteEvents=\(max(0, noteEventCount))",
                "tempoEvents=\(max(0, tempoEventCount))",
                "controllerEvents=\(max(0, controllerEventCount))",
                "annotations=\(max(0, annotationCount))",
                "unsupportedNotes=\(max(0, unsupportedNoteCount))",
                "approximations=\(max(0, approximationCount))",
                "stepMismatches=\(max(0, stepMismatchCount))",
                "highlightMismatches=\(max(0, highlightMismatchCount))",
                "notationMismatches=\(max(0, notationMismatchCount))",
            ].joined(separator: ";"),
            songID: songID,
            scoreRevision: scoreRevision,
            persistence: .systemOnly
        )
    }

    private var outcome: PianoPerformanceDiagnosticOutcome {
        if stepMismatchCount > 0 || highlightMismatchCount > 0 || notationMismatchCount > 0 { return .mismatch }
        if unsupportedNoteCount > 0 { return .unsupported }
        return .succeeded
    }
}

struct PianoPerformanceNotationFallbackDiagnosticSample: Equatable {
    private struct Key: Hashable {
        let kind: ScoreNotationProjection.Fallback.Kind
        let sourceKindToken: String?
        let reason: ScoreNotationProjection.Fallback.Reason
    }

    let kind: ScoreNotationProjection.Fallback.Kind
    let sourceKindToken: String?
    let reason: ScoreNotationProjection.Fallback.Reason
    let count: Int

    static func aggregated(from fallbacks: [ScoreNotationProjection.Fallback]) -> [Self] {
        Dictionary(grouping: fallbacks) { fallback in
            Key(kind: fallback.kind, sourceKindToken: fallback.sourceKindToken, reason: fallback.reason)
        }.map { key, values in
            Self(kind: key.kind, sourceKindToken: key.sourceKindToken, reason: key.reason, count: values.count)
        }.sorted {
            if $0.kind.rawValue != $1.kind.rawValue { return $0.kind.rawValue < $1.kind.rawValue }
            if ($0.sourceKindToken ?? "") != ($1.sourceKindToken ?? "") {
                return ($0.sourceKindToken ?? "") < ($1.sourceKindToken ?? "")
            }
            return $0.reason.rawValue < $1.reason.rawValue
        }
    }

    var diagnosticEvent: DiagnosticEvent {
        DiagnosticEvent(
            severity: .warning,
            code: .pianoPerformancePipeline,
            category: .pianoPerformance,
            stage: PianoPerformanceDiagnosticStage.plan.rawValue,
            summary: "记谱降级聚合",
            reason: [
                "kind=\(kind.rawValue)",
                "count=\(max(0, count))",
                "reason=\(reason.rawValue)",
                "sourceKind=\(sourceKindToken ?? "unspecified")",
            ].joined(separator: ";"),
            persistence: .systemOnly
        )
    }
}
