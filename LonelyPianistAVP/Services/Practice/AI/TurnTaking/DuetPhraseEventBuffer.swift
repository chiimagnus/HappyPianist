import Foundation
import ImprovProtocol

/// A pure-logic buffer which records MIDI control changes during a phrase and flushes them using the
/// same trim/rebase/window strategy as `DuetPhraseBuffer`.
struct DuetPhraseEventBuffer: Sendable {
    struct RecordedControlChange: Equatable, Sendable {
        let controller: Int
        let value: Int
        let timestampSeconds: TimeInterval
    }

    private var phraseStartTimestampSeconds: TimeInterval?
    private var recordedControlChanges: [RecordedControlChange] = []
    private var latestKnownControlValues: [Int: Int] = [:]

    init() {}

    mutating func recordPhraseStartIfNeeded(timestampSeconds: TimeInterval) {
        if phraseStartTimestampSeconds == nil {
            phraseStartTimestampSeconds = timestampSeconds

            let injected = latestKnownControlValues
                .filter { Self.allowedControllers.contains($0.key) }
                .map { controller, value in
                    RecordedControlChange(controller: controller, value: value, timestampSeconds: timestampSeconds)
                }
                .sorted { lhs, rhs in
                    if lhs.controller != rhs.controller { return lhs.controller < rhs.controller }
                    return lhs.value < rhs.value
                }
            recordedControlChanges.append(contentsOf: injected)
        }
    }

    mutating func recordControlChange(controller: Int, value: Int, timestampSeconds: TimeInterval) {
        guard Self.allowedControllers.contains(controller) else { return }
        latestKnownControlValues[controller] = value
        guard phraseStartTimestampSeconds != nil else { return }

        recordedControlChanges.append(
            RecordedControlChange(
                controller: controller,
                value: value,
                timestampSeconds: timestampSeconds
            )
        )
    }

    mutating func flushPhrase(flushedPhrase: DuetPhraseBuffer.FlushResult) -> [ImprovEvent] {
        defer { reset() }
        guard let base = phraseStartTimestampSeconds else { return [] }
        guard recordedControlChanges.isEmpty == false else { return [] }

        let rebased = recordedControlChanges.map { change in
            RecordedControlChange(
                controller: change.controller,
                value: change.value,
                timestampSeconds: max(0, change.timestampSeconds - base)
            )
        }.sorted { lhs, rhs in
            if lhs.timestampSeconds != rhs.timestampSeconds { return lhs.timestampSeconds < rhs.timestampSeconds }
            if lhs.controller != rhs.controller { return lhs.controller < rhs.controller }
            return lhs.value < rhs.value
        }

        let phraseEndTimeSeconds = flushedPhrase.untrimmedEndTimeSeconds
        if phraseEndTimeSeconds <= 10 {
            return rebased
                .filter { $0.timestampSeconds <= phraseEndTimeSeconds + 1e-9 }
                .map { ImprovEvent.cc(controller: $0.controller, value: $0.value, time: $0.timestampSeconds) }
        }

        let windowStartSeconds = max(0, phraseEndTimeSeconds - 15)
        let windowEvents = rebased
            .filter { $0.timestampSeconds >= windowStartSeconds }
            .map { change in
                ImprovEvent.cc(
                    controller: change.controller,
                    value: change.value,
                    time: max(0, change.timestampSeconds - windowStartSeconds)
                )
            }
        let initialAtWindowStart: [ImprovEvent] = Self.allowedControllers.compactMap { controller in
            let lastChange = rebased.last(where: { $0.controller == controller && $0.timestampSeconds <= windowStartSeconds + 1e-9 })
            guard let lastChange else { return nil }
            return ImprovEvent.cc(controller: lastChange.controller, value: lastChange.value, time: 0)
        }

        return (initialAtWindowStart + windowEvents).sorted { lhs, rhs in
            if lhs.time != rhs.time { return lhs.time < rhs.time }
            if lhs.type != rhs.type { return lhs.type == .cc }
            return tieBreaker(lhs) < tieBreaker(rhs)
        }
    }

    mutating func reset() {
        phraseStartTimestampSeconds = nil
        recordedControlChanges.removeAll(keepingCapacity: true)
        latestKnownControlValues.removeAll(keepingCapacity: true)
    }

    private static let allowedControllers: Set<Int> = [7, 11, 64]

    private func tieBreaker(_ event: ImprovEvent) -> Int {
        switch event.type {
        case .cc:
            return (event.controller ?? 0) * 256 + (event.value ?? 0)
        case .note:
            return (event.note ?? 0) * 256 + (event.velocity ?? 0)
        }
    }
}
