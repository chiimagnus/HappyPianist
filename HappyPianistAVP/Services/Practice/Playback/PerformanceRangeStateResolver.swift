import Foundation

struct PerformanceRangeStateResolver {
    enum Approximation: Equatable, Sendable {
        case reattackedHeldNote(eventID: ScorePerformanceNoteEventID)
    }

    struct StartState: Equatable, Sendable {
        let tick: Int
        let tempo: ScorePerformanceTempoEvent?
        let controllers: [ScorePerformanceControllerEvent]
        let heldNotes: [PerformanceTransportReducer.Note]
        let approximations: [Approximation]
    }

    func resolve(
        plan: ScorePerformancePlan,
        at startTick: Int,
        practiceHandMode: PracticeHandMode
    ) -> StartState {
        let heldNotes = plan.noteEvents
            .filter {
                practiceHandMode.allows(hand: $0.handAssignment.hand)
                    && $0.performedOnTick < startTick
                    && $0.performedOffTick > startTick
            }
            .map {
                PerformanceTransportReducer.Note(
                    eventID: $0.id,
                    midiNote: $0.midiNote,
                    velocity: $0.velocity,
                    onTick: startTick,
                    offTick: $0.performedOffTick
                )
            }

        return StartState(
            tick: startTick,
            tempo: tempoState(plan.tempoEvents, at: startTick),
            controllers: controllerStates(plan.controllerEvents, at: startTick),
            heldNotes: heldNotes,
            approximations: heldNotes.map { .reattackedHeldNote(eventID: $0.eventID) }
        )
    }

    private func tempoState(
        _ events: [ScorePerformanceTempoEvent],
        at startTick: Int
    ) -> ScorePerformanceTempoEvent? {
        guard events.contains(where: { $0.tick == startTick }) == false,
              let event = events.enumerated()
              .filter({ $0.element.tick < startTick })
              .max(by: indexedTempoOrder)?
              .element
        else {
            return nil
        }
        let continuesRamp = event.endTick.map { startTick < $0 } ?? false
        let quarterBPM: Double
        if let endTick = event.endTick,
           let endQuarterBPM = event.endQuarterBPM,
           endTick > event.tick {
            let progress = min(1, Double(startTick - event.tick) / Double(endTick - event.tick))
            quarterBPM = event.quarterBPM + (endQuarterBPM - event.quarterBPM) * progress
        } else {
            quarterBPM = event.quarterBPM
        }
        return ScorePerformanceTempoEvent(
            sourceDirectionID: event.sourceDirectionID,
            performedOccurrenceIndex: event.performedOccurrenceIndex,
            tick: startTick,
            quarterBPM: quarterBPM,
            endTick: continuesRamp ? event.endTick : nil,
            endQuarterBPM: continuesRamp ? event.endQuarterBPM : nil
        )
    }

    private func controllerStates(
        _ events: [ScorePerformanceControllerEvent],
        at startTick: Int
    ) -> [ScorePerformanceControllerEvent] {
        let explicitControllers = Set(events.lazy.filter { $0.tick == startTick }.map(\.controllerNumber))
        return Dictionary(grouping: events.enumerated().filter { $0.element.tick < startTick }) {
            $0.element.controllerNumber
        }.compactMap { controller, candidates in
            guard explicitControllers.contains(controller) == false,
                  let event = candidates.max(by: indexedControllerOrder)?.element
            else {
                return nil
            }
            return ScorePerformanceControllerEvent(
                sourceDirectionID: event.sourceDirectionID,
                performedOccurrenceIndex: event.performedOccurrenceIndex,
                tick: startTick,
                controllerNumber: event.controllerNumber,
                value: event.value,
                outputCapabilityRequirement: event.outputCapabilityRequirement
            )
        }.sorted { $0.controllerNumber < $1.controllerNumber }
    }

    private func indexedTempoOrder(
        _ lhs: EnumeratedSequence<[ScorePerformanceTempoEvent]>.Element,
        _ rhs: EnumeratedSequence<[ScorePerformanceTempoEvent]>.Element
    ) -> Bool {
        if lhs.element.tick != rhs.element.tick { return lhs.element.tick < rhs.element.tick }
        return lhs.offset < rhs.offset
    }

    private func indexedControllerOrder(
        _ lhs: EnumeratedSequence<[ScorePerformanceControllerEvent]>.Element,
        _ rhs: EnumeratedSequence<[ScorePerformanceControllerEvent]>.Element
    ) -> Bool {
        if lhs.element.tick != rhs.element.tick { return lhs.element.tick < rhs.element.tick }
        return lhs.offset < rhs.offset
    }
}
