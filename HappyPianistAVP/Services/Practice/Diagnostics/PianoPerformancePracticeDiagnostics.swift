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

enum PianoPerformanceCoachingDiagnosticOutcome: String, Equatable {
    case issued
    case accepted
    case skipped
    case remeasured
}

enum PianoPerformanceConfidenceBucket: String, Equatable {
    case unavailable
    case low
    case medium
    case high

    init(_ confidence: Double?) {
        guard let confidence else {
            self = .unavailable
            return
        }
        switch confidence {
        case ..<0.6: self = .low
        case ..<0.85: self = .medium
        default: self = .high
        }
    }
}

struct PianoPerformanceCoachingMetricSnapshot: Equatable {
    let dimension: PerformanceAssessmentDimension
    let outcome: PracticeEvidenceOutcome
    let evidenceStatus: PerformanceAssessmentEvidenceStatus
    let measurement: PerformanceAssessmentMeasurement?
    let sampleCount: Int

    init(_ result: PerformanceAssessmentDimensionResult) {
        dimension = result.dimension
        outcome = result.outcome
        evidenceStatus = result.evidenceStatus
        measurement = result.measurement
        sampleCount = result.sampleCount
    }
}

struct PianoPerformanceCoachingDiagnosticSample: Equatable {
    let decisionID: UUID
    let outcome: PianoPerformanceCoachingDiagnosticOutcome
    let issueKind: MusicalIssueKind
    let confidenceBucket: PianoPerformanceConfidenceBucket
    let actionKind: CoachingActionKind
    let before: PianoPerformanceCoachingMetricSnapshot
    let after: PianoPerformanceCoachingMetricSnapshot?
    let completionMet: Bool?

    var diagnosticEvent: DiagnosticEvent {
        DiagnosticEvent(
            severity: .info,
            code: .pianoPerformancePipeline,
            category: .pianoPerformance,
            stage: PianoPerformanceDiagnosticStage.coaching.rawValue,
            summary: "指导决策状态",
            reason: [
                "outcome=\(outcome.rawValue)",
                "issue=\(issueKind.rawValue)",
                "confidence=\(confidenceBucket.rawValue)",
                "action=\(actionKind.rawValue)",
                metricFields(before, prefix: "before"),
                metricFields(after, prefix: "after"),
                "completion=\(completionMet.map { $0 ? "met" : "unmet" } ?? "unavailable")",
            ].joined(separator: ";"),
            operationID: decisionID,
            persistence: .systemOnly
        )
    }

    private func metricFields(_ metric: PianoPerformanceCoachingMetricSnapshot?, prefix: String) -> String {
        guard let metric else { return "\(prefix)=unavailable" }
        let measurement = metric.measurement.map { "\($0.value):\($0.unit.rawValue)" } ?? "unavailable"
        return [
            "\(prefix)Dimension=\(metric.dimension.rawValue)",
            "\(prefix)Outcome=\(metric.outcome.rawValue)",
            "\(prefix)Evidence=\(metric.evidenceStatus.rawValue)",
            "\(prefix)Measurement=\(measurement)",
            "\(prefix)Samples=\(max(0, metric.sampleCount))",
        ].joined(separator: ";")
    }
}
