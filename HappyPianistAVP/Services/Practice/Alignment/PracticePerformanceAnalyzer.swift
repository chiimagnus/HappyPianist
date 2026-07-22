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
    private var measureSpans: [MusicXMLMeasureSpan] = []
    private var activeTickRange: Range<Int>?
    private var roundStart: PerformanceMonotonicInstant?
    private var aligner: IncrementalPerformanceAligner?
    private var latestAlignment: PerformanceAlignment?
    private var latestAssessment: PassagePerformanceAssessment?
    private var inputCapabilities = PerformanceInputCapabilities.unavailable
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

    func configure(
        plan: ScorePerformancePlan,
        measureSpans: [MusicXMLMeasureSpan],
        activeTickRange: Range<Int>?,
        tempoScale: Double = 1
    ) {
        reset()
        self.plan = Self.scaledPlan(plan, tempoScale: tempoScale)
        self.measureSpans = measureSpans
        self.activeTickRange = activeTickRange
    }

    func beginRound(at start: PerformanceMonotonicInstant) {
        roundGeneration += 1
        roundStart = start
        aligner = makeAligner(at: start)
        latestAlignment = nil
        latestAssessment = nil
        inputCapabilities = .unavailable
        acceptedObservationCount = 0
        rejectedObservationCount = 0
        alignmentLatencyMilliseconds = nil
    }

    func record(_ observation: PerformanceObservation) {
        if aligner == nil {
            aligner = makeAligner(at: roundStart ?? observation.alignmentTimestamp)
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
        updateAssessment()
    }

    func registerInputCapabilities(_ capabilities: PerformanceInputCapabilities) {
        inputCapabilities = inputCapabilities.merging(capabilities)
        updateAssessment()
    }

    func finishRound() async -> PracticePerformanceAnalyzerSnapshot {
        if var current = aligner, current.state == .running {
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
        measureSpans = []
        activeTickRange = nil
        roundStart = nil
        aligner = nil
        latestAlignment = nil
        latestAssessment = nil
        inputCapabilities = .unavailable
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
            measureSpans: measureSpans,
            inputCapabilities: inputCapabilities,
            tickRange: activeTickRange
        )
    }

    private func makeAligner(
        at start: PerformanceMonotonicInstant
    ) -> IncrementalPerformanceAligner? {
        guard let plan else { return nil }
        var aligner = IncrementalPerformanceAligner()
        aligner.start(
            plan: plan,
            generation: nil,
            performanceStart: start,
            activeTickRange: activeTickRange
        )
        return aligner
    }

    private static func scaledPlan(
        _ plan: ScorePerformancePlan,
        tempoScale: Double
    ) -> ScorePerformancePlan {
        guard tempoScale.isFinite, tempoScale > 0, tempoScale != 1 else { return plan }
        let tempoEvents = MusicXMLTempoMap(performanceEvents: plan.tempoEvents)
            .performanceEvents()
            .map { event in
                ScorePerformanceTempoEvent(
                    sourceDirectionID: event.sourceDirectionID,
                    performedOccurrenceIndex: event.performedOccurrenceIndex,
                    tick: event.tick,
                    quarterBPM: event.quarterBPM * tempoScale,
                    endTick: event.endTick,
                    endQuarterBPM: event.endQuarterBPM.map { $0 * tempoScale }
                )
            }
        return ScorePerformancePlan(
            id: plan.id,
            sourceScoreIdentity: plan.sourceScoreIdentity,
            order: plan.order,
            resolution: plan.resolution,
            noteEvents: plan.noteEvents,
            tempoEvents: tempoEvents,
            controllerEvents: plan.controllerEvents,
            annotations: plan.annotations,
            approximations: plan.approximations
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
        guard let assessment = snapshot.assessment else { return }
        let dimensions = assessment.dimensions
        let unknownCount = dimensions.count(where: { $0.outcome == .unknown })
        let coverage = assessment.evidenceCoverage.ratio
        _ = await diagnosticsReporter.record(DiagnosticEvent(
            severity: .info,
            code: .pianoPerformancePipeline,
            category: .practiceSession,
            stage: PianoPerformanceDiagnosticStage.assessment.rawValue,
            summary: "演奏评估已完成",
            reason: "rubric=\(assessment.rubricVersion.rawValue),dimensions=\(dimensions.count),coverage=\(Self.ratioBucket(coverage)),unknownRatio=\(Self.ratioBucket(Self.ratio(unknownCount, dimensions.count))),correct=\(dimensions.count(where: { $0.outcome == .correct })),incorrect=\(dimensions.count(where: { $0.outcome == .incorrect })),unknown=\(unknownCount),insufficient=\(dimensions.count(where: { $0.outcome == .insufficientEvidence })),observed=\(dimensions.count(where: { $0.evidenceStatus == .observed })),degraded=\(dimensions.count(where: { $0.evidenceStatus == .degraded }))",
            persistence: .systemOnly
        ))
    }

    private static func ratio(_ numerator: Int, _ denominator: Int) -> Double? {
        guard denominator > 0 else { return nil }
        return Double(numerator) / Double(denominator)
    }

    private static func ratioBucket(_ ratio: Double?) -> String {
        guard let ratio else { return "none" }
        if ratio == 0 { return "zero" }
        if ratio < 0.25 { return "low" }
        if ratio < 0.75 { return "medium" }
        if ratio < 1 { return "high" }
        return "full"
    }
}
