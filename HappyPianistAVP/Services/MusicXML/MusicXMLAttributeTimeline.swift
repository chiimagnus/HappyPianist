import Foundation

struct MusicXMLAttributeTimeline: Equatable {
    private let timeSignatureEvents: [MusicXMLTimeSignatureEvent]
    private let keySignatureEvents: [MusicXMLKeySignatureEvent]
    private let clefEvents: [MusicXMLClefEvent]

    init(
        timeSignatureEvents: [MusicXMLTimeSignatureEvent],
        keySignatureEvents: [MusicXMLKeySignatureEvent],
        clefEvents: [MusicXMLClefEvent]
    ) {
        self.timeSignatureEvents = timeSignatureEvents.sorted { $0.tick < $1.tick }
        self.keySignatureEvents = keySignatureEvents.sorted { $0.tick < $1.tick }
        self.clefEvents = clefEvents.sorted { $0.tick < $1.tick }
    }

    func timeSignature(
        atTick tick: Int,
        partID: String? = nil,
        staffNumber: Int? = nil
    ) -> MusicXMLTimeSignatureEvent? {
        lastApplicable(
            atOrBeforeTick: tick,
            events: timeSignatureEvents,
            partID: partID,
            staffNumber: staffNumber,
            scope: \.scope,
            eventTick: \.tick
        )
    }

    func meter(atTick tick: Int, partID: String? = nil, staffNumber: Int? = nil) -> MusicXMLMeter? {
        timeSignature(atTick: tick, partID: partID, staffNumber: staffNumber)?.meter
    }

    func keySignature(
        atTick tick: Int,
        partID: String? = nil,
        staffNumber: Int? = nil
    ) -> MusicXMLKeySignatureEvent? {
        lastApplicable(
            atOrBeforeTick: tick,
            events: keySignatureEvents,
            partID: partID,
            staffNumber: staffNumber,
            scope: \.scope,
            eventTick: \.tick
        )
    }

    func clef(atTick tick: Int, partID: String? = nil, staffNumber: Int) -> MusicXMLClefEvent? {
        let filtered = clefEvents.filter { event in
            let eventStaff = event.scope.staff ?? event.numberToken.flatMap(Int.init) ?? 1
            return (partID == nil || event.scope.partID == partID) && eventStaff == staffNumber
        }
        return filtered.last { $0.tick <= max(0, tick) }
    }

    private func lastApplicable<Event>(
        atOrBeforeTick tick: Int,
        events: [Event],
        partID: String?,
        staffNumber: Int?,
        scope: KeyPath<Event, MusicXMLEventScope>,
        eventTick: KeyPath<Event, Int>
    ) -> Event? {
        let clamped = max(0, tick)
        // ponytail: attribute changes are sparse; index per staff only if real-score profiling shows this scan matters.
        return events
            .filter { event in
                let eventScope = event[keyPath: scope]
                return event[keyPath: eventTick] <= clamped &&
                    (partID == nil || eventScope.partID == partID) &&
                    (staffNumber == nil ? eventScope.staff == nil : eventScope.staff == nil || eventScope.staff == staffNumber)
            }
            .max { lhs, rhs in
                let lhsTick = lhs[keyPath: eventTick]
                let rhsTick = rhs[keyPath: eventTick]
                if lhsTick != rhsTick { return lhsTick < rhsTick }
                return lhs[keyPath: scope].staff == nil && rhs[keyPath: scope].staff != nil
            }
    }
}
