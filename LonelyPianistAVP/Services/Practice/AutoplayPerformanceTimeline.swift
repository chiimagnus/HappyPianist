import Foundation

nonisolated struct AutoplayPerformanceTimeline: Equatable, Sendable {
    enum EventKind: Equatable, Sendable {
        case pauseSeconds(TimeInterval)
        case noteOff(midi: Int)
        case pedalDown
        case pedalUp
        case noteOn(midi: Int, velocity: UInt8)
        case advanceStep(index: Int)
        case advanceGuide(index: Int, guideID: Int)
    }

    struct Event: Equatable, Identifiable, Sendable {
        let id: Int
        let tick: Int
        let kind: EventKind

        var sortPriority: Int {
            switch kind {
                case .pauseSeconds:
                    return 0
                case .noteOff:
                    return 1
                case .pedalDown, .pedalUp:
                    return 2
                case .noteOn:
                    return 3
                case .advanceStep:
                    return 4
                case .advanceGuide:
                    return 5
            }
        }
    }

    static let empty = AutoplayPerformanceTimeline(events: [])

    let events: [Event]

    func firstEventIndex(atOrAfter tick: Int) -> Int {
        var low = 0
        var high = events.count
        while low < high {
            let mid = (low + high) / 2
            if events[mid].tick < tick {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }

    static func build(
        guides: [PianoHighlightGuide],
        steps: [PracticeStep],
        pedalTimeline: MusicXMLPedalTimeline,
        fermataTimeline: MusicXMLFermataTimeline,
        tempoMap: MusicXMLTempoMap
    ) -> AutoplayPerformanceTimeline {
        var rawEvents: [(tick: Int, priority: Int, kind: EventKind)] = []
        rawEvents.reserveCapacity(guides.count + steps.count + 16)

        for (index, guide) in guides.enumerated() {
            rawEvents.append((tick: guide.tick, priority: 5, kind: .advanceGuide(index: index, guideID: guide.id)))
        }

        for (index, step) in steps.enumerated() {
            rawEvents.append((tick: step.tick, priority: 4, kind: .advanceStep(index: index)))
        }

        for interval in normalizedNoteIntervals(from: guides) {
            rawEvents.append((tick: interval.onTick, priority: 3, kind: .noteOn(midi: interval.midi, velocity: interval.velocity)))
            rawEvents.append((tick: interval.offTick, priority: 1, kind: .noteOff(midi: interval.midi)))
        }

        var pedalEventsByTick: [Int: Set<PedalEventKind>] = [:]
        var cursor = -1
        while let change = pedalTimeline.nextChange(afterTick: cursor) {
            pedalEventsByTick[change.tick, default: []].insert(change.isDown ? .down : .up)
            cursor = change.tick
        }
        for releaseTick in pedalTimeline.releaseEdges() {
            pedalEventsByTick[releaseTick, default: []].insert(.up)
            if pedalTimeline.isDown(atTick: releaseTick) {
                pedalEventsByTick[releaseTick, default: []].insert(.down)
            }
        }
        for (tick, events) in pedalEventsByTick {
            if events.contains(.up) {
                rawEvents.append((tick: tick, priority: 2, kind: .pedalUp))
            }
            if events.contains(.down) {
                rawEvents.append((tick: tick, priority: 2, kind: .pedalDown))
            }
        }

        for pair in zip(steps, steps.dropFirst()) {
            let current = pair.0
            let next = pair.1
            let staffs = Set(current.notes.map { $0.staff ?? 1 })
            let extraSeconds = fermataTimeline.extraHoldSeconds(
                atTick: current.tick,
                staffs: staffs,
                tempoMap: tempoMap
            )
            if extraSeconds > 0 {
                rawEvents.append((tick: next.tick, priority: 0, kind: .pauseSeconds(extraSeconds)))
            }
        }

        let sortedEvents = rawEvents
            .sorted { lhs, rhs in
                if lhs.tick != rhs.tick { return lhs.tick < rhs.tick }
                if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
                return eventTieBreaker(lhs.kind) < eventTieBreaker(rhs.kind)
            }
            .enumerated()
            .map { offset, event in
                Event(id: offset, tick: event.tick, kind: event.kind)
            }

        return AutoplayPerformanceTimeline(events: sortedEvents)
    }

    private enum PedalEventKind: Hashable {
        case up
        case down
    }

    private struct NoteInterval: Equatable {
        let midi: Int
        let velocity: UInt8
        let onTick: Int
        var offTick: Int
    }

    private static func normalizedNoteIntervals(from guides: [PianoHighlightGuide]) -> [NoteInterval] {
        var grouped: [String: NoteInterval] = [:]

        for guide in guides where guide.kind == .trigger {
            for note in guide.triggeredNotes {
                let key = "\(note.onTick):\(note.midiNote)"
                if var existing = grouped[key] {
                    existing.offTick = max(existing.offTick, note.offTick)
                    existing = NoteInterval(
                        midi: existing.midi,
                        velocity: max(existing.velocity, note.velocity),
                        onTick: existing.onTick,
                        offTick: max(existing.onTick + 1, existing.offTick)
                    )
                    grouped[key] = existing
                } else {
                    grouped[key] = NoteInterval(
                        midi: note.midiNote,
                        velocity: note.velocity,
                        onTick: note.onTick,
                        offTick: max(note.onTick + 1, note.offTick)
                    )
                }
            }
        }

        var intervals = grouped.values.sorted { lhs, rhs in
            if lhs.midi != rhs.midi { return lhs.midi < rhs.midi }
            if lhs.onTick != rhs.onTick { return lhs.onTick < rhs.onTick }
            return lhs.offTick < rhs.offTick
        }

        var lastIndexByMIDI: [Int: Int] = [:]
        for index in intervals.indices {
            let midi = intervals[index].midi
            if let previousIndex = lastIndexByMIDI[midi], intervals[previousIndex].offTick > intervals[index].onTick {
                intervals[previousIndex].offTick = intervals[index].onTick
            }
            lastIndexByMIDI[midi] = index
        }

        return intervals.filter { $0.offTick > $0.onTick }
    }

    private static func eventTieBreaker(_ kind: EventKind) -> String {
        switch kind {
            case let .noteOff(midi):
                return "noteOff-\(midi)"
            case let .noteOn(midi, velocity):
                return "noteOn-\(midi)-\(velocity)"
            case let .advanceStep(index):
                return "advanceStep-\(index)"
            case let .advanceGuide(index, guideID):
                return "advanceGuide-\(index)-\(guideID)"
            case .pedalDown:
                return "pedal-1-down"
            case .pedalUp:
                return "pedal-0-up"
            case let .pauseSeconds(seconds):
                return "pause-\(seconds)"
        }
    }
}
