import Diagnostics
import Foundation

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
