import Foundation

struct PerformanceTransportReducer {
    struct TransportState: Equatable, Sendable {
        let generation: Int
        let startTick: Int?
        let activeEventIDs: Set<ScorePerformanceNoteEventID>

        var isPlaying: Bool {
            startTick != nil
        }

        static let idle = TransportState(
            generation: 0,
            startTick: nil,
            activeEventIDs: []
        )
    }

    enum ResetReason: Equatable, Sendable {
        case seek
        case loop
        case end
        case stop
    }

    enum Boundary: Equatable, Sendable {
        case start(tick: Int, activeEventIDs: Set<ScorePerformanceNoteEventID>)
        case seek(tick: Int, activeEventIDs: Set<ScorePerformanceNoteEventID>)
        case loop(tick: Int, activeEventIDs: Set<ScorePerformanceNoteEventID>)
        case end
        case stop
    }

    enum LifecycleCommand: Equatable, Sendable {
        case reset(
            eventIDs: [ScorePerformanceNoteEventID],
            reason: ResetReason,
            generation: Int
        )
        case apply(
            tick: Int,
            eventIDs: [ScorePerformanceNoteEventID],
            generation: Int
        )
    }

    struct Transition: Equatable, Sendable {
        let state: TransportState
        let commands: [LifecycleCommand]
    }

    struct Note: Equatable, Sendable {
        let eventID: ScorePerformanceNoteEventID
        let midiNote: Int
        let velocity: UInt8
        let onTick: Int
        let offTick: Int
    }

    struct Command: Equatable, Sendable {
        enum Kind: Equatable, Sendable {
            case noteOff
            case noteOn(velocity: UInt8)
        }

        let eventID: ScorePerformanceNoteEventID
        let midiNote: Int
        let tick: Int
        let kind: Kind
    }

    struct Reduction: Equatable, Sendable {
        let commands: [Command]
        let retriggeredEventCount: Int
        let preventedStaleOffCount: Int
        let orphanOffCount: Int
    }

    func transition(from state: TransportState, at boundary: Boundary) -> Transition {
        switch boundary {
        case let .start(tick, activeEventIDs):
            guard state.isPlaying == false else {
                return Transition(state: state, commands: [])
            }
            return applyingState(
                from: state,
                tick: tick,
                activeEventIDs: activeEventIDs,
                resetReason: nil
            )

        case let .seek(tick, activeEventIDs):
            return applyingState(
                from: state,
                tick: tick,
                activeEventIDs: activeEventIDs,
                resetReason: .seek
            )

        case let .loop(tick, activeEventIDs):
            return applyingState(
                from: state,
                tick: tick,
                activeEventIDs: activeEventIDs,
                resetReason: .loop
            )

        case .end:
            return stopping(from: state, reason: .end)

        case .stop:
            return stopping(from: state, reason: .stop)
        }
    }

    func reduce(notes: [Note]) -> Reduction {
        let edges = notes.flatMap { note in
            [
                Edge(eventID: note.eventID, midiNote: note.midiNote, tick: note.onTick, kind: .on(note.velocity)),
                Edge(eventID: note.eventID, midiNote: note.midiNote, tick: note.offTick, kind: .off),
            ]
        }.sorted(by: edgeOrder)
        var activeByMIDI: [Int: [ScorePerformanceNoteEventID: Int]] = [:]
        var supersededEventIDs: Set<ScorePerformanceNoteEventID> = []
        var commands: [Command] = []
        var retriggeredEventCount = 0
        var preventedStaleOffCount = 0
        var orphanOffCount = 0

        for edge in edges {
            switch edge.kind {
            case .off:
                if supersededEventIDs.remove(edge.eventID) != nil {
                    preventedStaleOffCount += 1
                } else if activeByMIDI[edge.midiNote]?.removeValue(forKey: edge.eventID) != nil {
                    commands.append(Command(
                        eventID: edge.eventID,
                        midiNote: edge.midiNote,
                        tick: edge.tick,
                        kind: .noteOff
                    ))
                } else {
                    orphanOffCount += 1
                }
                if activeByMIDI[edge.midiNote]?.isEmpty == true {
                    activeByMIDI[edge.midiNote] = nil
                }

            case let .on(velocity):
                let retriggeredEventIDs = (activeByMIDI[edge.midiNote] ?? [:])
                    .filter { $0.value < edge.tick }
                    .map(\.key)
                    .sorted { $0.description < $1.description }
                for eventID in retriggeredEventIDs {
                    activeByMIDI[edge.midiNote]?[eventID] = nil
                    supersededEventIDs.insert(eventID)
                    retriggeredEventCount += 1
                    commands.append(Command(
                        eventID: eventID,
                        midiNote: edge.midiNote,
                        tick: edge.tick,
                        kind: .noteOff
                    ))
                }
                activeByMIDI[edge.midiNote, default: [:]][edge.eventID] = edge.tick
                commands.append(Command(
                    eventID: edge.eventID,
                    midiNote: edge.midiNote,
                    tick: edge.tick,
                    kind: .noteOn(velocity: velocity)
                ))
            }
        }

        return Reduction(
            commands: commands,
            retriggeredEventCount: retriggeredEventCount,
            preventedStaleOffCount: preventedStaleOffCount,
            orphanOffCount: orphanOffCount
        )
    }
}

private extension PerformanceTransportReducer {
    func applyingState(
        from state: TransportState,
        tick: Int,
        activeEventIDs: Set<ScorePerformanceNoteEventID>,
        resetReason: ResetReason?
    ) -> Transition {
        let generation = state.generation + 1
        let sortedTargetEventIDs = sorted(activeEventIDs)
        var commands: [LifecycleCommand] = []
        if let resetReason {
            commands.append(.reset(
                eventIDs: sorted(state.activeEventIDs),
                reason: resetReason,
                generation: generation
            ))
        }
        commands.append(.apply(
            tick: tick,
            eventIDs: sortedTargetEventIDs,
            generation: generation
        ))
        return Transition(
            state: TransportState(
                generation: generation,
                startTick: tick,
                activeEventIDs: activeEventIDs
            ),
            commands: commands
        )
    }

    func stopping(from state: TransportState, reason: ResetReason) -> Transition {
        guard state.isPlaying else {
            return Transition(state: state, commands: [])
        }
        let generation = state.generation + 1
        return Transition(
            state: TransportState(
                generation: generation,
                startTick: nil,
                activeEventIDs: []
            ),
            commands: [
                .reset(
                    eventIDs: sorted(state.activeEventIDs),
                    reason: reason,
                    generation: generation
                ),
            ]
        )
    }

    func sorted(_ eventIDs: Set<ScorePerformanceNoteEventID>) -> [ScorePerformanceNoteEventID] {
        eventIDs.sorted { $0.description < $1.description }
    }

    struct Edge {
        enum Kind {
            case off
            case on(UInt8)
        }

        let eventID: ScorePerformanceNoteEventID
        let midiNote: Int
        let tick: Int
        let kind: Kind
    }

    func edgeOrder(_ lhs: Edge, _ rhs: Edge) -> Bool {
        if lhs.tick != rhs.tick { return lhs.tick < rhs.tick }
        let lhsPriority = edgePriority(lhs.kind)
        let rhsPriority = edgePriority(rhs.kind)
        if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
        if lhs.midiNote != rhs.midiNote { return lhs.midiNote < rhs.midiNote }
        return lhs.eventID.description < rhs.eventID.description
    }

    func edgePriority(_ kind: Edge.Kind) -> Int {
        switch kind {
        case .off: 0
        case .on: 1
        }
    }
}
