import Foundation
import Practice

/// Continuous-duet sustain context. Only CC64 is part of the observed Companion/Aria prompt state.
struct DuetPhraseEventBuffer {
    struct Snapshot: Equatable {
        let promptEvents: [ImprovEvent]
        let sustainValue: Int
        let phraseProvenance: CreativeDuetPhraseProvenance

        init(
            promptEvents: [ImprovEvent],
            sustainValue: Int,
            phraseProvenance: CreativeDuetPhraseProvenance = .empty
        ) {
            self.promptEvents = promptEvents
            self.sustainValue = sustainValue
            self.phraseProvenance = phraseProvenance
        }
    }

    private struct RecordedSustainChange: Equatable {
        let value: Int
        let timestampSeconds: TimeInterval
        let provenance: CreativeDuetPhraseProvenance.Observation
    }

    private struct PromptSustainChange: Equatable {
        let event: ImprovEvent
        let provenance: CreativeDuetPhraseProvenance.Observation
    }

    private var recordedChanges: [RecordedSustainChange] = []
    private var latestValue = 0
    private var latestTimestamp: TimeInterval?
    private var latestProvenance: CreativeDuetPhraseProvenance.Observation?

    private static let maxHistorySeconds: TimeInterval = 12.0

    var sustainValue: Int { latestValue }

    init() {}

    mutating func record(_ event: PerformanceObservationPhraseAdapter.PhraseEvent) {
        guard case let .controlChange(controller, value) = event.kind, controller == 64 else { return }

        let timestampSeconds = event.timestamp.seconds
        pruneHistory(nowTimestampSeconds: timestampSeconds)
        latestValue = value
        latestTimestamp = timestampSeconds
        latestProvenance = event.provenance
        recordedChanges.append(
            RecordedSustainChange(
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
        let latestEventTime = recordedChanges.map(\.timestampSeconds).max() ?? nowTimestampSeconds
        let windowStart = max(lookbackStart, latestEventTime - max(0.5, maxPromptSeconds))
        let windowEnd = max(nowTimestampSeconds, latestEventTime)

        let initialEvent: PromptSustainChange? = {
            if let beforeWindow = recordedChanges.last(where: { $0.timestampSeconds < windowStart }) {
                return PromptSustainChange(
                    event: .cc(controller: 64, value: beforeWindow.value, time: 0),
                    provenance: beforeWindow.provenance
                )
            }
            guard latestTimestamp.map({ $0 < windowStart }) == true,
                  let latestProvenance
            else { return nil }
            return PromptSustainChange(
                event: .cc(controller: 64, value: latestValue, time: 0),
                provenance: latestProvenance
            )
        }()

        let promptChanges = recordedChanges.compactMap { change -> PromptSustainChange? in
            guard change.timestampSeconds >= windowStart, change.timestampSeconds <= windowEnd else { return nil }
            return PromptSustainChange(
                event: .cc(
                    controller: 64,
                    value: change.value,
                    time: max(0, change.timestampSeconds - windowStart)
                ),
                provenance: change.provenance
            )
        }

        var combined = promptChanges
        if let initialEvent {
            combined.append(initialEvent)
        }
        combined.sort { $0.event.time < $1.event.time }

        return Snapshot(
            promptEvents: combined.map(\.event),
            sustainValue: latestValue,
            phraseProvenance: .init(observations: combined.map(\.provenance))
        )
    }

    mutating func reset() {
        recordedChanges.removeAll(keepingCapacity: true)
        latestValue = 0
        latestTimestamp = nil
        latestProvenance = nil
    }

    private mutating func pruneHistory(nowTimestampSeconds: TimeInterval) {
        let cutoff = nowTimestampSeconds - Self.maxHistorySeconds
        recordedChanges.removeAll { $0.timestampSeconds < cutoff }
    }
}
