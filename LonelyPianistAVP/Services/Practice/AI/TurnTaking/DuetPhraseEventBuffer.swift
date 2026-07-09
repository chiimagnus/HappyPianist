import Foundation
import ImprovProtocol

/// Continuous-duet CC context. Records rolling control changes instead of phrase-bounded events.
struct DuetPhraseEventBuffer: Sendable {
    struct Snapshot: Equatable, Sendable {
        let promptEvents: [ImprovEvent]
        let latestValues: [Int: Int]
        let sustainValue: Int
    }

    private struct RecordedControlChange: Equatable, Sendable {
        let controller: Int
        let value: Int
        let timestampSeconds: TimeInterval
    }

    private var recordedControlChanges: [RecordedControlChange] = []
    private var latestKnownControlValues: [Int: Int] = [:]

    private static let allowedControllers: Set<Int> = [7, 11, 64]
    private static let maxHistorySeconds: TimeInterval = 12.0

    init() {}

    mutating func recordControlChange(controller: Int, value: Int, timestampSeconds: TimeInterval) {
        guard Self.allowedControllers.contains(controller) else { return }
        pruneHistory(nowTimestampSeconds: timestampSeconds)
        latestKnownControlValues[controller] = value
        recordedControlChanges.append(
            RecordedControlChange(controller: controller, value: value, timestampSeconds: timestampSeconds)
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

        let initialEvents: [ImprovEvent] = Self.allowedControllers.compactMap { controller in
            if let beforeWindow = recordedControlChanges.last(where: { $0.controller == controller && $0.timestampSeconds <= windowStart }) {
                return ImprovEvent.cc(controller: beforeWindow.controller, value: beforeWindow.value, time: 0)
            }
            guard let currentValue = latestKnownControlValues[controller] else { return nil }
            return ImprovEvent.cc(controller: controller, value: currentValue, time: 0)
        }

        let promptEvents = recordedControlChanges.compactMap { change -> ImprovEvent? in
            guard change.timestampSeconds >= windowStart, change.timestampSeconds <= windowEnd else { return nil }
            return ImprovEvent.cc(
                controller: change.controller,
                value: change.value,
                time: max(0, change.timestampSeconds - windowStart)
            )
        }

        let combined = (initialEvents + promptEvents).sorted { lhs, rhs in
            if lhs.time != rhs.time { return lhs.time < rhs.time }
            return (lhs.controller ?? 0) < (rhs.controller ?? 0)
        }

        return Snapshot(
            promptEvents: combined,
            latestValues: latestKnownControlValues,
            sustainValue: latestKnownControlValues[64] ?? 0
        )
    }

    mutating func reset() {
        recordedControlChanges.removeAll(keepingCapacity: true)
        latestKnownControlValues.removeAll(keepingCapacity: true)
    }

    private mutating func pruneHistory(nowTimestampSeconds: TimeInterval) {
        let cutoff = nowTimestampSeconds - Self.maxHistorySeconds
        recordedControlChanges.removeAll { $0.timestampSeconds < cutoff }
    }
}
