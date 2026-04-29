import Foundation

enum AutoplayCursorEvent: Equatable, Sendable {
    case step(index: Int)
    case guide(index: Int, guideID: Int)
}

struct AutoplayTimelineTimeCursor: Equatable, Sendable {
    private struct TimedEvent: Equatable, Sendable {
        let timeSeconds: TimeInterval
        let event: AutoplayCursorEvent
    }

    private let scheduled: [TimedEvent]
    private var nextIndex: Int

    init(
        timeline: AutoplayPerformanceTimeline,
        tickToSeconds: (Int) -> TimeInterval,
        startTick: Int
    ) {
        let baseTick = max(0, startTick)
        let baseSeconds = tickToSeconds(baseTick)

        let startIndex = timeline.firstEventIndex(atOrAfter: baseTick)
        var pausePrefixSeconds: TimeInterval = 0

        var scheduled: [TimedEvent] = []
        scheduled.reserveCapacity(128)

        for event in timeline.events[startIndex...] {
            switch event.kind {
                case let .pauseSeconds(seconds):
                    pausePrefixSeconds += seconds

                case let .advanceStep(index):
                    scheduled.append(
                        TimedEvent(
                            timeSeconds: tickToSeconds(event.tick) - baseSeconds + pausePrefixSeconds,
                            event: .step(index: index)
                        )
                    )

                case let .advanceGuide(index, guideID):
                    scheduled.append(
                        TimedEvent(
                            timeSeconds: tickToSeconds(event.tick) - baseSeconds + pausePrefixSeconds,
                            event: .guide(index: index, guideID: guideID)
                        )
                    )

                case .noteOn, .noteOff, .pedalDown, .pedalUp:
                    continue
            }
        }

        self.scheduled = scheduled
        nextIndex = 0
    }

    mutating func advance(toSeconds now: TimeInterval) -> [AutoplayCursorEvent] {
        var emitted: [AutoplayCursorEvent] = []
        while nextIndex < scheduled.count, scheduled[nextIndex].timeSeconds <= now {
            emitted.append(scheduled[nextIndex].event)
            nextIndex += 1
        }
        return emitted
    }
}

