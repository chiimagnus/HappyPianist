import Foundation

struct CoachingDecisionService: Sendable {
    private let exercisePolicy: PracticeExercisePolicy
    private let priorityPolicy: CoachingPriorityPolicy

    init(
        exercisePolicy: PracticeExercisePolicy = PracticeExercisePolicy(),
        priorityPolicy: CoachingPriorityPolicy = CoachingPriorityPolicy()
    ) {
        self.exercisePolicy = exercisePolicy
        self.priorityPolicy = priorityPolicy
    }

    func decision(
        for assessment: PassagePerformanceAssessment,
        context: CoachingPriorityContext = CoachingPriorityContext()
    ) -> CoachingDecision? {
        priorityPolicy.primaryDecision(from: candidates(for: assessment), context: context)
    }

    func candidates(for assessment: PassagePerformanceAssessment) -> [CoachingDecision] {
        issues(from: assessment).compactMap { issue in
            exercisePolicy.action(for: issue).map { CoachingDecision(issue: issue, action: $0) }
        }
    }

    private func issues(from assessment: PassagePerformanceAssessment) -> [MusicalIssue] {
        assessmentScopes(assessment).flatMap { scope in
            issues(
                in: scope.dimensions,
                scoreRange: scope.scoreRange,
                measureOccurrenceIDs: scope.measureOccurrenceIDs,
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
    ) -> [(
        scoreRange: Range<Int>,
        measureOccurrenceIDs: [PracticeMeasureOccurrenceID],
        dimensions: [PerformanceAssessmentDimensionResult]
    )] {
        guard assessment.measures.isEmpty == false else {
            return [(assessment.tickRange, [], assessment.dimensions)]
        }
        return Dictionary(grouping: assessment.measures, by: \.tickRange)
            .map { range, measures in
                (
                    range,
                    measures.map(\.occurrenceID).sorted(by: Self.occurrenceOrder),
                    measures.flatMap(\.dimensions)
                )
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
        measureOccurrenceIDs: [PracticeMeasureOccurrenceID],
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
                measureOccurrenceIDs: measureOccurrenceIDs,
                dimensionResults: results,
                confidence: confidence,
                provenance: provenance
            )
        }
    }

    private static func occurrenceOrder(
        _ lhs: PracticeMeasureOccurrenceID,
        _ rhs: PracticeMeasureOccurrenceID
    ) -> Bool {
        if lhs.occurrenceIndex != rhs.occurrenceIndex {
            return lhs.occurrenceIndex < rhs.occurrenceIndex
        }
        if lhs.sourceMeasureID.partID != rhs.sourceMeasureID.partID {
            return lhs.sourceMeasureID.partID < rhs.sourceMeasureID.partID
        }
        return lhs.sourceMeasureID.sourceMeasureIndex < rhs.sourceMeasureID.sourceMeasureIndex
    }
}
