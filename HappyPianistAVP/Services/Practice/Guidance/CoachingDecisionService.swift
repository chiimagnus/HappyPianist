import Foundation

struct CoachingDecisionService: Sendable {
    private let exercisePolicy: PracticeExercisePolicy

    init(exercisePolicy: PracticeExercisePolicy = PracticeExercisePolicy()) {
        self.exercisePolicy = exercisePolicy
    }

    func decision(for assessment: PassagePerformanceAssessment) -> CoachingDecision? {
        decisions(for: assessment).first
    }

    func decisions(for assessment: PassagePerformanceAssessment) -> [CoachingDecision] {
        issues(from: assessment).compactMap { issue in
            exercisePolicy.action(for: issue).map { CoachingDecision(issue: issue, action: $0) }
        }
    }

    private func issues(from assessment: PassagePerformanceAssessment) -> [MusicalIssue] {
        assessmentScopes(assessment).flatMap { scope in
            issues(
                in: scope.dimensions,
                scoreRange: scope.scoreRange,
                provenance: MusicalIssueProvenance(
                    planID: assessment.planID,
                    sourceGeneration: assessment.sourceGeneration,
                    rubricVersion: assessment.rubricVersion
                )
            )
        }
    }

    private func assessmentScopes(
        _ assessment: PassagePerformanceAssessment
    ) -> [(scoreRange: Range<Int>, dimensions: [PerformanceAssessmentDimensionResult])] {
        guard assessment.measures.isEmpty == false else {
            return [(assessment.tickRange, assessment.dimensions)]
        }
        return Dictionary(grouping: assessment.measures, by: \.tickRange)
            .map { range, measures in
                (range, measures.flatMap(\.dimensions))
            }
            .sorted { lhs, rhs in
                if lhs.0.lowerBound != rhs.0.lowerBound {
                    return lhs.0.lowerBound < rhs.0.lowerBound
                }
                return lhs.0.upperBound < rhs.0.upperBound
            }
    }

    private func issues(
        in dimensions: [PerformanceAssessmentDimensionResult],
        scoreRange: Range<Int>,
        provenance: MusicalIssueProvenance
    ) -> [MusicalIssue] {
        var orderedKinds: [MusicalIssueKind] = []
        var resultsByKind: [MusicalIssueKind: [PerformanceAssessmentDimensionResult]] = [:]

        for result in dimensions {
            let kind: MusicalIssueKind
            switch result.outcome {
            case .correct:
                continue
            case .incorrect:
                kind = result.dimension.musicalIssueKind
            case .unknown, .insufficientEvidence:
                kind = .evidence
            }
            if resultsByKind[kind] == nil {
                orderedKinds.append(kind)
            }
            resultsByKind[kind, default: []].append(result)
        }

        return orderedKinds.compactMap { kind in
            guard let results = resultsByKind[kind], results.isEmpty == false else { return nil }
            let confidenceValues = results.compactMap(\.confidence)
            let confidence = confidenceValues.count == results.count ? confidenceValues.min() : nil
            return MusicalIssue(
                kind: kind,
                scoreRange: scoreRange,
                dimensionResults: results,
                confidence: confidence,
                provenance: provenance
            )
        }
    }
}
