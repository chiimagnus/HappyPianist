import Foundation

public enum AutoplayCursorEvent: Equatable, Sendable {
    case step(index: Int)
    case guide(index: Int, guideID: Int)
}

public struct AutoplayTimelineTimeSchedule: Equatable, Sendable {
    public struct ScheduledCursorEvent: Equatable, Sendable {
        public let timeSeconds: TimeInterval
        public let tick: Int
        public let event: AutoplayCursorEvent
    }

    public let scheduledCursorEvents: [ScheduledCursorEvent]
    private let timeSecondsByEventID: [Int: TimeInterval]
    private let timeSecondsByTick: [Int: TimeInterval]

    public init(
        timeline: AutoplayPerformanceTimeline,
        tickToSeconds: (Int) -> TimeInterval,
        startTick: Int,
        leadInSeconds: TimeInterval = 0
    ) {
        let baseTick = max(0, startTick)
        let baseSeconds = tickToSeconds(baseTick)
        let startIndex = timeline.firstEventIndex(atOrAfter: baseTick)

        var pausePrefixSeconds: TimeInterval = 0
        var cursorEvents: [ScheduledCursorEvent] = []
        var eventTimes: [Int: TimeInterval] = [:]
        var tickTimes: [Int: TimeInterval] = [:]
        cursorEvents.reserveCapacity(128)
        eventTimes.reserveCapacity(max(16, timeline.events.count - startIndex))

        for event in timeline.events[startIndex...] {
            if case let .pauseSeconds(seconds) = event.kind {
                pausePrefixSeconds += seconds
            }
            let timeSeconds = tickToSeconds(event.tick) - baseSeconds + pausePrefixSeconds + leadInSeconds
            eventTimes[event.id] = timeSeconds
            tickTimes[event.tick] = timeSeconds

            switch event.kind {
            case let .advanceStep(index):
                cursorEvents.append(ScheduledCursorEvent(
                    timeSeconds: timeSeconds,
                    tick: event.tick,
                    event: .step(index: index)
                ))
            case let .advanceGuide(index, guideID):
                cursorEvents.append(ScheduledCursorEvent(
                    timeSeconds: timeSeconds,
                    tick: event.tick,
                    event: .guide(index: index, guideID: guideID)
                ))
            case .pauseSeconds, .noteOn, .noteOff, .controlChange, .tempo:
                continue
            }
        }

        scheduledCursorEvents = cursorEvents
        timeSecondsByEventID = eventTimes
        timeSecondsByTick = tickTimes
    }

    public func timeSeconds(forEventID eventID: Int) -> TimeInterval? {
        timeSecondsByEventID[eventID]
    }

    public func timeSeconds(atTick tick: Int) -> TimeInterval? {
        timeSecondsByTick[tick]
    }

}

public struct AutoplayTimelineTimeCursor: Equatable {
    private let scheduled: [AutoplayTimelineTimeSchedule.ScheduledCursorEvent]
    private var nextIndex: Int

    public init(
        timeline: AutoplayPerformanceTimeline,
        tickToSeconds: (Int) -> TimeInterval,
        startTick: Int,
        leadInSeconds: TimeInterval = 0
    ) {
        self.init(schedule: AutoplayTimelineTimeSchedule(
            timeline: timeline,
            tickToSeconds: tickToSeconds,
            startTick: startTick,
            leadInSeconds: leadInSeconds
        ))
    }

    public init(schedule: AutoplayTimelineTimeSchedule) {
        scheduled = schedule.scheduledCursorEvents
        nextIndex = 0
    }

    public var isFinished: Bool {
        nextIndex >= scheduled.count
    }

    public mutating func advance(toSeconds now: TimeInterval) -> [AutoplayCursorEvent] {
        var emitted: [AutoplayCursorEvent] = []
        while nextIndex < scheduled.count, scheduled[nextIndex].timeSeconds <= now {
            emitted.append(scheduled[nextIndex].event)
            nextIndex += 1
        }
        return emitted
    }
}
