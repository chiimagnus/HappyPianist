import Foundation

enum RecordedTakeAlignmentError: Error, Equatable {
    case scoreIdentityMismatch
    case missingObservation
}

struct RecordedTakeAlignmentSegment: Equatable, Sendable {
    let tickRange: Range<Int>
    let alignment: PerformanceAlignment
}

struct RecordedTakeAlignmentDiagnostics: Equatable, Sendable {
    let takeSchemaVersion: Int
    let eventCount: Int
    let observationCount: Int
    let segmentCount: Int
    let alignedCount: Int
    let missingCount: Int
    let extraCount: Int
    let ambiguousCount: Int
    let unknownCount: Int
    let controllerLinkCount: Int
    let performedOccurrenceCount: Int
}

struct RecordedTakeAlignmentResult: Equatable, Sendable {
    let global: PerformanceAlignment
    let segments: [RecordedTakeAlignmentSegment]
    let diagnostics: RecordedTakeAlignmentDiagnostics
}

struct RecordedTakeAligner: Sendable {
    private let engine: PerformanceAlignmentEngine

    init(engine: PerformanceAlignmentEngine = .init()) {
        self.engine = engine
    }

    func alignResult(
        take: RecordingTake,
        plan: ScorePerformancePlan,
        segmentTickRanges: [Range<Int>] = []
    ) throws -> RecordedTakeAlignmentResult {
        let observations = try validatedObservations(from: take, plan: plan)
        let global = replay(observations: observations, plan: plan, activeTickRange: nil)
        let segments = segmentTickRanges.map { range in
            let lowerSeconds = engine.performanceSeconds(plan: plan, atTick: range.lowerBound)
            let upperSeconds = engine.performanceSeconds(plan: plan, atTick: range.upperBound)
            let selected = observations.filter {
                lowerSeconds <= $0.alignmentTimestamp.seconds
                    && $0.alignmentTimestamp.seconds < upperSeconds
            }
            return RecordedTakeAlignmentSegment(
                tickRange: range,
                alignment: replay(observations: selected, plan: plan, activeTickRange: range)
            )
        }
        let counts = Self.linkCounts(global.links)
        return RecordedTakeAlignmentResult(
            global: global,
            segments: segments,
            diagnostics: RecordedTakeAlignmentDiagnostics(
                takeSchemaVersion: take.schemaVersion,
                eventCount: take.events.count,
                observationCount: observations.count,
                segmentCount: segments.count,
                alignedCount: counts.aligned,
                missingCount: counts.missing,
                extraCount: counts.extra,
                ambiguousCount: counts.ambiguous,
                unknownCount: counts.unknown,
                controllerLinkCount: global.controllerLinks.count,
                performedOccurrenceCount: Set(plan.noteEvents.map(\.performedOccurrenceIndex)).count
            )
        )
    }

    private func replay(
        observations: [PerformanceObservation],
        plan: ScorePerformancePlan,
        activeTickRange: Range<Int>?
    ) -> PerformanceAlignment {
        var incremental = IncrementalPerformanceAligner(
            engine: engine,
            configuration: .init(maximumBufferedObservations: observations.count)
        )
        incremental.start(
            plan: plan,
            generation: nil,
            performanceStart: .init(seconds: 0),
            activeTickRange: activeTickRange
        )
        incremental.appendReplayObservations(observations)
        return incremental.finish() ?? PerformanceAlignment(
            planID: plan.id,
            sourceGeneration: 0,
            links: []
        )
    }

    private func validatedObservations(
        from take: RecordingTake,
        plan: ScorePerformancePlan
    ) throws -> [PerformanceObservation] {
        guard take.metadata.scoreIdentity == plan.sourceScoreIdentity else {
            throw RecordedTakeAlignmentError.scoreIdentityMismatch
        }
        guard let observations = take.alignmentObservations() else {
            throw RecordedTakeAlignmentError.missingObservation
        }
        return observations.enumerated().sorted { lhs, rhs in
            if lhs.element.alignmentTimestamp != rhs.element.alignmentTimestamp {
                return lhs.element.alignmentTimestamp < rhs.element.alignmentTimestamp
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    private static func linkCounts(
        _ links: [PerformanceAlignmentLink]
    ) -> (aligned: Int, missing: Int, extra: Int, ambiguous: Int, unknown: Int) {
        links.reduce(into: (0, 0, 0, 0, 0)) { counts, link in
            switch link {
            case .aligned: counts.0 += 1
            case .missing: counts.1 += 1
            case .extra: counts.2 += 1
            case .ambiguous: counts.3 += 1
            case .unknown: counts.4 += 1
            case .provisional: break
            }
        }
    }
}
