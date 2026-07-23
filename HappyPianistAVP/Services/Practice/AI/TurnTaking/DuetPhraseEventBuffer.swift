import Foundation

/// Continuous-duet CC context. Records rolling control changes instead of phrase-bounded events.
struct DuetPhraseEventBuffer {
    struct Snapshot: Equatable {
        let promptEvents: [ImprovEvent]
        let latestValues: [Int: Int]
        let sustainValue: Int
        let phraseProvenance: CreativeDuetPhraseProvenance

        init(
            promptEvents: [ImprovEvent],
            latestValues: [Int: Int],
            sustainValue: Int,
            phraseProvenance: CreativeDuetPhraseProvenance = .empty
        ) {
            self.promptEvents = promptEvents
            self.latestValues = latestValues
            self.sustainValue = sustainValue
            self.phraseProvenance = phraseProvenance
        }
    }

    private struct RecordedControlChange: Equatable {
        let controller: Int
        let value: Int
        let timestampSeconds: TimeInterval
        let provenance: CreativeDuetPhraseProvenance.Observation
    }

    private struct PromptControlChange: Equatable {
        let event: ImprovEvent
        let provenance: CreativeDuetPhraseProvenance.Observation
    }

    private var recordedControlChanges: [RecordedControlChange] = []
    private var latestKnownControlValues: [Int: Int] = [:]
    private var latestKnownControlTimestamps: [Int: TimeInterval] = [:]
    private var latestKnownControlProvenances: [Int: CreativeDuetPhraseProvenance.Observation] = [:]

    private static let allowedControllers: Set<Int> = [7, 11, 64]
    private static let maxHistorySeconds: TimeInterval = 12.0

    var sustainValue: Int {
        latestKnownControlValues[64] ?? 0
    }

    init() {}

    mutating func record(_ event: PerformanceObservationPhraseAdapter.PhraseEvent) {
        guard case let .controlChange(controller, value) = event.kind else { return }
        guard Self.allowedControllers.contains(controller) else { return }

        let timestampSeconds = event.timestamp.seconds
        pruneHistory(nowTimestampSeconds: timestampSeconds)
        latestKnownControlValues[controller] = value
        latestKnownControlTimestamps[controller] = timestampSeconds
        latestKnownControlProvenances[controller] = event.provenance
        recordedControlChanges.append(
            RecordedControlChange(
                controller: controller,
                value: value,
                timestampSeconds: timestampSeconds,
                provenance: event.provenance
            )
        )
    }

    mutating func snapshot(
        nowTimestampSeconds: TimeInterval,
        lookbackSeconds: TimeInterval,
        maxPromptSeconds: TimeInterval
    ) -> Snapshot {
        pruneHistory(nowTimestampSeconds: nowTimestampSeconds)

        let lookbackStart = max(0, nowTimestampSeconds - max(0, lookbackSeconds))
        let latestEventTime = recordedControlChanges.map(\.timestampSeconds).max() ?? nowTimestampSeconds
        let windowStart = max(lookbackStart, latestEventTime - max(0.5, maxPromptSeconds))
        let windowEnd = max(nowTimestampSeconds, latestEventTime)

        let initialEvents: [PromptControlChange] = Self.allowedControllers.compactMap { controller in
            if let beforeWindow = recordedControlChanges.last(where: { $0.controller == controller && $0.timestampSeconds < windowStart }) {
                return PromptControlChange(
                    event: .cc(controller: beforeWindow.controller, value: beforeWindow.value, time: 0),
                    provenance: beforeWindow.provenance
                )
            }
            guard latestKnownControlTimestamps[controller].map({ $0 < windowStart }) == true,
                  let currentValue = latestKnownControlValues[controller],
                  let provenance = latestKnownControlProvenances[controller]
            else { return nil }
            return PromptControlChange(
                event: .cc(controller: controller, value: currentValue, time: 0),
                provenance: provenance
            )
        }

        let promptEvents = recordedControlChanges.compactMap { change -> PromptControlChange? in
            guard change.timestampSeconds >= windowStart, change.timestampSeconds <= windowEnd else { return nil }
            return PromptControlChange(
                event: .cc(
                    controller: change.controller,
                    value: change.value,
                    time: max(0, change.timestampSeconds - windowStart)
                ),
                provenance: change.provenance
            )
        }

        let combined = (initialEvents + promptEvents).sorted { lhs, rhs in
            if lhs.event.time != rhs.event.time { return lhs.event.time < rhs.event.time }
            return (lhs.event.controller ?? 0) < (rhs.event.controller ?? 0)
        }

        return Snapshot(
            promptEvents: combined.map(\.event),
            latestValues: latestKnownControlValues,
            sustainValue: latestKnownControlValues[64] ?? 0,
            phraseProvenance: .init(observations: combined.map(\.provenance))
        )
    }

    mutating func reset() {
        recordedControlChanges.removeAll(keepingCapacity: true)
        latestKnownControlValues.removeAll(keepingCapacity: true)
        latestKnownControlTimestamps.removeAll(keepingCapacity: true)
        latestKnownControlProvenances.removeAll(keepingCapacity: true)
    }

    private mutating func pruneHistory(nowTimestampSeconds: TimeInterval) {
        let cutoff = nowTimestampSeconds - Self.maxHistorySeconds
        recordedControlChanges.removeAll { $0.timestampSeconds < cutoff }
    }
}
