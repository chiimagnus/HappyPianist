import Foundation

struct MusicXMLPedalTimeline: Equatable {
    struct ControllerChange: Equatable, Sendable {
        let sourceDirectionID: MusicXMLDirectionSourceID?
        let performedOccurrenceIndex: Int
        let tick: Int
        let controllerNumber: UInt8
        let value: UInt8
    }

    private let controllers: [ControllerChange]

    init(events: [MusicXMLPedalEvent]) {
        controllers = events
            .enumerated()
            .compactMap { offset, event -> (offset: Int, change: ControllerChange)? in
                guard let value = event.value else { return nil }
                return (
                    offset,
                    ControllerChange(
                        sourceDirectionID: event.sourceID,
                        performedOccurrenceIndex: event.performedOccurrenceIndex,
                        tick: event.tick,
                        controllerNumber: event.controller.rawValue,
                        value: value.midiValue
                    )
                )
            }
            .sorted { lhs, rhs in
                if lhs.change.tick != rhs.change.tick { return lhs.change.tick < rhs.change.tick }
                if lhs.change.controllerNumber != rhs.change.controllerNumber {
                    return lhs.change.controllerNumber < rhs.change.controllerNumber
                }
                return lhs.offset < rhs.offset
            }
            .map(\.change)
    }

    func controllerChanges() -> [ControllerChange] {
        controllers
    }
}
