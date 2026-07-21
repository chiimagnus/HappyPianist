import Foundation

enum RecordedTakeAlignmentError: Error, Equatable {
    case scoreIdentityMismatch
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
    let controllerLinkCount: Int
    let performedOccurrenceCount: Int
    let usedLegacyProjection: Bool
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
        (try? alignResult(
            take: take,
            plan: plan,
            segmentTickRanges: activeTickRange.map { [$0] } ?? []
        ).global) ?? PerformanceAlignment(
            planID: plan.id,
            sourceGeneration: 0,
            links: []
        )
    }

    func alignResult(
        take: RecordingTake,
        plan: ScorePerformancePlan,
        segmentTickRanges: [Range<Int>] = []
    ) throws -> RecordedTakeAlignmentResult {
        if let takeIdentity = take.metadata.scoreIdentity,
           takeIdentity != plan.sourceScoreIdentity
        {
            throw RecordedTakeAlignmentError.scoreIdentityMismatch
        }
        let observations = take.alignmentObservations()
        let global = replay(observations: observations, plan: plan, activeTickRange: nil)
        let segments = segmentTickRanges.map { range in
            let lowerSeconds = engine.performanceSeconds(plan: plan, atTick: range.lowerBound)
            let upperSeconds = engine.performanceSeconds(plan: plan, atTick: range.upperBound)
            let selected = observations.filter {
                (lowerSeconds ... upperSeconds).contains($0.alignmentTimestamp.seconds)
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
                controllerLinkCount: global.controllerLinks.count,
                performedOccurrenceCount: Set(plan.noteEvents.map(\.performedOccurrenceIndex)).count,
                usedLegacyProjection: take.events.contains { $0.observation == nil }
            )
        )
    }

    private func replay(
        observations: [PerformanceObservation],
        plan: ScorePerformancePlan,
        activeTickRange: Range<Int>?
    ) -> PerformanceAlignment {
        var incremental = IncrementalPerformanceAligner(engine: engine)
        incremental.start(
            plan: plan,
            generation: observations.first?.source.generation ?? 0,
            performanceStart: .init(seconds: 0),
            activeTickRange: activeTickRange
        )
        for observation in observations {
            _ = incremental.append(observation)
        }
        return incremental.finish() ?? PerformanceAlignment(
            planID: plan.id,
            sourceGeneration: 0,
            links: []
        )
    }

    private static func linkCounts(
        _ links: [PerformanceAlignmentLink]
    ) -> (aligned: Int, missing: Int, extra: Int, ambiguous: Int) {
        links.reduce(into: (0, 0, 0, 0)) { counts, link in
            switch link {
            case .aligned: counts.0 += 1
            case .missing: counts.1 += 1
            case .extra: counts.2 += 1
            case .ambiguous: counts.3 += 1
            case .provisional: break
            }
        }
    }
}
