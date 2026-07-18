import Foundation

struct PerformanceRangeStateResolver {
    enum Approximation: Equatable, Sendable {
        case reattackedHeldNote(eventID: ScorePerformanceNoteEventID)
        case reattackedSustainedNote(eventID: ScorePerformanceNoteEventID)
    }

    struct StartState: Equatable, Sendable {
        let tick: Int
        let tempo: ScorePerformanceTempoEvent?
        let controllers: [ScorePerformanceControllerEvent]
        let heldNotes: [PerformanceTransportReducer.Note]
        let approximations: [Approximation]
    }

    struct EndState: Equatable, Sendable {
        let tick: Int
        let controllerResets: [ScorePerformanceControllerEvent]
    }

    func resolve(
        plan: ScorePerformancePlan,
        at startTick: Int,
        practiceHandMode: PracticeHandMode
    ) -> StartState {
        let sustainEvents = plan.controllerEvents.enumerated()
            .filter { $0.element.controllerNumber == 64 }
            .sorted(by: indexedControllerOrder)
        let sustainIntervalStart = currentSustainIntervalStart(sustainEvents, at: startTick)
        let nextSustainReleaseTick = sustainEvents.first {
            $0.element.tick > startTick && $0.element.value < 64
        }?.element.tick
        let planEndTick = max(
            startTick + 1,
            plan.noteEvents.map(\.performedOffTick).max() ?? startTick + 1
        )
        var heldNotes: [PerformanceTransportReducer.Note] = []
        var approximations: [Approximation] = []

        for note in plan.noteEvents where
            practiceHandMode.allows(hand: note.handAssignment.hand) && note.performedOnTick < startTick
        {
            let approximation: Approximation
            let offTick: Int
            if note.performedOffTick > startTick {
                approximation = .reattackedHeldNote(eventID: note.id)
                offTick = note.performedOffTick
            } else if let sustainIntervalStart, note.performedOffTick > sustainIntervalStart {
                approximation = .reattackedSustainedNote(eventID: note.id)
                offTick = nextSustainReleaseTick ?? planEndTick
            } else {
                continue
            }
            heldNotes.append(PerformanceTransportReducer.Note(
                eventID: note.id,
                midiNote: note.midiNote,
                velocity: note.velocity,
                onTick: startTick,
                offTick: offTick
            ))
            approximations.append(approximation)
        }

        return StartState(
            tick: startTick,
            tempo: tempoState(plan.tempoEvents, at: startTick),
            controllers: controllerStates(plan.controllerEvents, at: startTick),
            heldNotes: heldNotes,
            approximations: approximations
        )
    }

    func resolveEnd(plan: ScorePerformancePlan, at endTick: Int) -> EndState {
        let sustain = plan.controllerEvents.enumerated()
            .filter { $0.element.controllerNumber == 64 && $0.element.tick < endTick }
            .max(by: indexedControllerOrder)?
            .element
        let controllerResets: [ScorePerformanceControllerEvent]
        if let sustain, sustain.value != 0 {
            controllerResets = [ScorePerformanceControllerEvent(
                sourceDirectionID: nil,
                performedOccurrenceIndex: sustain.performedOccurrenceIndex,
                tick: endTick,
                controllerNumber: sustain.controllerNumber,
                value: 0,
                outputCapabilityRequirement: sustain.outputCapabilityRequirement
            )]
        } else {
            controllerResets = []
        }
        return EndState(tick: endTick, controllerResets: controllerResets)
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

    private func currentSustainIntervalStart(
        _ events: [EnumeratedSequence<[ScorePerformanceControllerEvent]>.Element],
        at startTick: Int
    ) -> Int? {
        // ponytail: sounding-note reconstruction uses the MIDI CC64 switch point; playback still forwards exact values.
        var intervalStart: Int?
        for event in events.lazy.map(\.element) where event.tick <= startTick {
            if event.value >= 64 {
                intervalStart = intervalStart ?? event.tick
            } else {
                intervalStart = nil
            }
        }
        return intervalStart
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
