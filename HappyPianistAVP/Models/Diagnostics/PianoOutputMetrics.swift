import Foundation

struct PianoOutputTimestampObservation: Equatable, Sendable {
    let scheduledAtSeconds: TimeInterval
    let submittedAtSeconds: TimeInterval?
    let acknowledgedAtSeconds: TimeInterval?
}

struct PianoOutputMetricsSnapshot: Equatable, Sendable {
    let capability: PianoPerformanceDiagnosticCapability
    let scheduledCount: Int
    let submittedCount: Int
    let acknowledgedCount: Int
    let lateCount: Int
    let droppedCount: Int
    let cancelledCount: Int
    let resetSucceededCount: Int
    let resetFailedCount: Int
    let stuckNotePreventionCount: Int
    let submissionLatencyBuckets: [PianoPerformanceDurationBucket: Int]
    let acknowledgementLatencyBuckets: [PianoPerformanceDurationBucket: Int]
    let jitterBuckets: [PianoPerformanceDurationBucket: Int]

    var diagnosticEvent: DiagnosticEvent {
        let fields = [
            "capability=\(capability.rawValue)",
            "scheduled=\(scheduledCount)",
            "submitted=\(submittedCount)",
            "acknowledged=\(acknowledgedCount)",
            "late=\(lateCount)",
            "dropped=\(droppedCount)",
            "cancelled=\(cancelledCount)",
            "resetSucceeded=\(resetSucceededCount)",
            "resetFailed=\(resetFailedCount)",
            "stuckNotePrevention=\(stuckNotePreventionCount)",
        ] + bucketFields(prefix: "submissionLatency", counts: submissionLatencyBuckets)
            + bucketFields(prefix: "acknowledgementLatency", counts: acknowledgementLatencyBuckets)
            + bucketFields(prefix: "jitter", counts: jitterBuckets)

        return DiagnosticEvent(
            severity: severity,
            code: .pianoPerformancePipeline,
            category: .pianoPerformance,
            stage: "playback.outputMetrics",
            summary: "钢琴输出聚合指标",
            reason: fields.joined(separator: ";"),
            persistence: .exportable
        )
    }

    private var severity: DiagnosticSeverity {
        if droppedCount > 0 || resetFailedCount > 0 { return .error }
        if lateCount > 0 { return .warning }
        return .info
    }

    private func bucketFields(
        prefix: String,
        counts: [PianoPerformanceDurationBucket: Int]
    ) -> [String] {
        PianoPerformanceDurationBucket.allCases.map { bucket in
            "\(prefix).\(bucket.rawValue)=\(counts[bucket, default: 0])"
        }
    }
}

struct PianoOutputMetricsAccumulator: Sendable {
    private(set) var scheduledCount = 0
    private(set) var submittedCount = 0
    private(set) var acknowledgedCount = 0
    private(set) var lateCount = 0
    private(set) var droppedCount = 0
    private(set) var cancelledCount = 0
    private(set) var resetSucceededCount = 0
    private(set) var resetFailedCount = 0
    private(set) var stuckNotePreventionCount = 0

    private var submissionLatencyBuckets: [PianoPerformanceDurationBucket: Int] = [:]
    private var acknowledgementLatencyBuckets: [PianoPerformanceDurationBucket: Int] = [:]
    private var jitterBuckets: [PianoPerformanceDurationBucket: Int] = [:]
    private var previousSubmissionOffset: TimeInterval?

    var hasActivity: Bool {
        scheduledCount > 0 || resetSucceededCount > 0 || resetFailedCount > 0
    }

    mutating func record(_ observation: PianoOutputTimestampObservation) {
        guard observation.scheduledAtSeconds.isFinite else { return }
        scheduledCount += 1

        guard let submittedAtSeconds = observation.submittedAtSeconds,
              submittedAtSeconds.isFinite
        else {
            droppedCount += 1
            return
        }

        submittedCount += 1
        let submissionOffset = submittedAtSeconds - observation.scheduledAtSeconds
        if submissionOffset > 0 { lateCount += 1 }
        Self.increment(
            &submissionLatencyBuckets,
            seconds: max(0, submissionOffset)
        )
        if let previousSubmissionOffset {
            Self.increment(
                &jitterBuckets,
                seconds: abs(submissionOffset - previousSubmissionOffset)
            )
        }
        self.previousSubmissionOffset = submissionOffset

        guard let acknowledgedAtSeconds = observation.acknowledgedAtSeconds,
              acknowledgedAtSeconds.isFinite
        else { return }
        acknowledgedCount += 1
        Self.increment(
            &acknowledgementLatencyBuckets,
            seconds: max(0, acknowledgedAtSeconds - observation.scheduledAtSeconds)
        )
    }

    mutating func recordDropped(count: Int) {
        let count = max(0, count)
        scheduledCount += count
        droppedCount += count
    }

    mutating func recordCancelled(count: Int) {
        let count = max(0, count)
        scheduledCount += count
        cancelledCount += count
    }

    mutating func recordReset(succeeded: Bool, preventsStuckNotes: Bool) {
        if succeeded {
            resetSucceededCount += 1
        } else {
            resetFailedCount += 1
        }
        if preventsStuckNotes {
            stuckNotePreventionCount += 1
        }
    }

    func snapshot(capability: PianoPerformanceDiagnosticCapability) -> PianoOutputMetricsSnapshot {
        PianoOutputMetricsSnapshot(
            capability: capability,
            scheduledCount: scheduledCount,
            submittedCount: submittedCount,
            acknowledgedCount: acknowledgedCount,
            lateCount: lateCount,
            droppedCount: droppedCount,
            cancelledCount: cancelledCount,
            resetSucceededCount: resetSucceededCount,
            resetFailedCount: resetFailedCount,
            stuckNotePreventionCount: stuckNotePreventionCount,
            submissionLatencyBuckets: submissionLatencyBuckets,
            acknowledgementLatencyBuckets: acknowledgementLatencyBuckets,
            jitterBuckets: jitterBuckets
        )
    }

    private static func increment(
        _ buckets: inout [PianoPerformanceDurationBucket: Int],
        seconds: TimeInterval
    ) {
        buckets[PianoPerformanceDurationBucket(seconds: seconds), default: 0] += 1
    }
}
