import Foundation

struct PracticePerformanceAnalyzerSnapshot: Equatable, Sendable {
    let roundGeneration: UInt64
    let alignment: PerformanceAlignment?
    let assessment: PassagePerformanceAssessment?
    let acceptedObservationCount: Int
    let rejectedObservationCount: Int
    let discardedObservationCount: Int
    let alignmentLatencyMilliseconds: Int64?
    let isRunning: Bool
}

actor PracticePerformanceAnalyzer {
    private let diagnosticsReporter: (any DiagnosticsReporting)?
    private let assessmentService: PerformanceAssessmentService
    private var plan: ScorePerformancePlan?
    private var activeTickRange: Range<Int>?
    private var roundStart: PerformanceMonotonicInstant?
    private var aligner: IncrementalPerformanceAligner?
    private var latestAlignment: PerformanceAlignment?
    private var latestAssessment: PassagePerformanceAssessment?
    private var acceptedObservationCount = 0
    private var rejectedObservationCount = 0
    private var alignmentLatencyMilliseconds: Int64?
    private var roundGeneration: UInt64 = 0

    init(
        diagnosticsReporter: (any DiagnosticsReporting)? = nil,
        assessmentService: PerformanceAssessmentService = PerformanceAssessmentService()
    ) {
        self.diagnosticsReporter = diagnosticsReporter
        self.assessmentService = assessmentService
    }

    func configure(plan: ScorePerformancePlan, activeTickRange: Range<Int>?) {
        reset()
        self.plan = plan
        self.activeTickRange = activeTickRange
    }

    func beginRound(at start: PerformanceMonotonicInstant) {
        roundGeneration += 1
        roundStart = start
        aligner = nil
        latestAlignment = nil
        latestAssessment = nil
        acceptedObservationCount = 0
        rejectedObservationCount = 0
        alignmentLatencyMilliseconds = nil
    }

    func record(_ observation: PerformanceObservation) {
        guard let plan else {
            rejectedObservationCount += 1
            return
        }
        if aligner == nil {
            var newAligner = IncrementalPerformanceAligner()
            let start = roundStart ?? observation.alignmentTimestamp
            newAligner.start(
                plan: plan,
                generation: nil,
                performanceStart: start,
                activeTickRange: activeTickRange
            )
            aligner = newAligner
        }
        guard var current = aligner,
              current.append(observation) != nil
        else {
            rejectedObservationCount += 1
            return
        }
        acceptedObservationCount += 1
        latestAlignment = current.appendSnapshot
        aligner = current
    }

    func finishRound() async -> PracticePerformanceAnalyzerSnapshot {
        if var current = aligner {
            let elapsed = ContinuousClock().measure {
                latestAlignment = current.finish()
            }
            alignmentLatencyMilliseconds = Int64((elapsed / .milliseconds(1)).rounded())
            aligner = current
            updateAssessment()
        }
        let snapshot = snapshot()
        await report(snapshot)
        return snapshot
    }

    func snapshot() -> PracticePerformanceAnalyzerSnapshot {
        PracticePerformanceAnalyzerSnapshot(
            roundGeneration: roundGeneration,
            alignment: latestAlignment,
            assessment: latestAssessment,
            acceptedObservationCount: acceptedObservationCount,
            rejectedObservationCount: rejectedObservationCount,
            discardedObservationCount: aligner?.discardedObservationCount ?? 0,
            alignmentLatencyMilliseconds: alignmentLatencyMilliseconds,
            isRunning: aligner?.state == .running
        )
    }

    func reset() {
        plan = nil
        activeTickRange = nil
        roundStart = nil
        aligner = nil
        latestAlignment = nil
        latestAssessment = nil
        acceptedObservationCount = 0
        rejectedObservationCount = 0
        alignmentLatencyMilliseconds = nil
    }

    private func updateAssessment() {
        guard let plan, let latestAlignment else {
            latestAssessment = nil
            return
        }
        latestAssessment = assessmentService.assess(
            plan: plan,
            alignment: latestAlignment,
            tickRange: activeTickRange
        )
    }

    private func report(_ snapshot: PracticePerformanceAnalyzerSnapshot) async {
        guard let diagnosticsReporter, let alignment = snapshot.alignment else { return }
        let aligned = alignment.links.filter { if case .aligned = $0 { true } else { false } }.count
        let missing = alignment.links.filter { if case .missing = $0 { true } else { false } }.count
        let extra = alignment.links.filter { if case .extra = $0 { true } else { false } }.count
        let ambiguous = alignment.links.filter { if case .ambiguous = $0 { true } else { false } }.count
        let unknown = alignment.links.filter { if case .unknown = $0 { true } else { false } }.count
        let candidates = alignment.links.reduce(into: 0) { count, link in
            switch link {
            case let .ambiguous(_, values), let .provisional(_, _, values):
                count += values.count
            case .aligned:
                count += 1
            case .missing, .extra, .unknown:
                break
            }
        }
        _ = await diagnosticsReporter.record(DiagnosticEvent(
            severity: .info,
            code: .pianoPerformancePipeline,
            category: .practiceSession,
            stage: "performanceAlignment",
            summary: "演奏对齐已完成",
            reason: "accepted=\(snapshot.acceptedObservationCount),rejected=\(snapshot.rejectedObservationCount),discarded=\(snapshot.discardedObservationCount),latencyMs=\(snapshot.alignmentLatencyMilliseconds ?? 0),candidates=\(candidates),aligned=\(aligned),missing=\(missing),extra=\(extra),ambiguous=\(ambiguous),unknown=\(unknown)",
            persistence: .systemOnly
        ))
    }
}
