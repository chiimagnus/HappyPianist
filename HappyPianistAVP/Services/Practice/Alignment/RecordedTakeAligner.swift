import Foundation

struct RecordedTakeAligner: Sendable {
    private let engine: PerformanceAlignmentEngine

    init(engine: PerformanceAlignmentEngine = .init()) {
        self.engine = engine
    }

    func candidateSnapshots(
        take: RecordingTake,
        plan: ScorePerformancePlan,
        activeTickRange: Range<Int>? = nil
    ) -> [PerformanceAlignmentCandidateSnapshot] {
        let observations = take.alignmentObservations()
        return engine.candidates(
            plan: plan,
            observations: observations,
            performanceStart: .init(seconds: 0),
            activeTickRange: activeTickRange
        )
    }

    func align(
        take: RecordingTake,
        plan: ScorePerformancePlan,
        activeTickRange: Range<Int>? = nil
    ) -> PerformanceAlignment {
        engine.align(
            plan: plan,
            observations: take.alignmentObservations(),
            performanceStart: .init(seconds: 0),
            activeTickRange: activeTickRange
        )
    }
}
