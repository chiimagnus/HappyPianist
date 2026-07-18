import Foundation

struct AutoplayPerformanceTimeline: Equatable {
    struct TransportMetrics: Equatable {
        static let empty = TransportMetrics(
            retriggeredEventCount: 0,
            preventedStaleOffCount: 0,
            orphanOffCount: 0
        )

        let retriggeredEventCount: Int
        let preventedStaleOffCount: Int
        let orphanOffCount: Int
    }

    enum EventKind: Equatable {
        case pauseSeconds(TimeInterval)
        case noteOff(midi: Int)
        case controlChange(controller: UInt8, value: UInt8)
        case tempo(quarterBPM: Double, endTick: Int?, endQuarterBPM: Double?)
        case noteOn(midi: Int, velocity: UInt8)
        case advanceStep(index: Int)
        case advanceGuide(index: Int, guideID: Int)
    }

    struct Event: Equatable, Identifiable {
        let id: Int
        let sourceEventID: String?
        let tick: Int
        let kind: EventKind

        init(id: Int, sourceEventID: String? = nil, tick: Int, kind: EventKind) {
            self.id = id
            self.sourceEventID = sourceEventID
            self.tick = tick
            self.kind = kind
        }

    }

    private struct RawEvent {
        let tick: Int
        let priority: Int
        let sourceEventID: String?
        let kind: EventKind
    }

    static let empty = AutoplayPerformanceTimeline(events: [])

    let events: [Event]
    let rangeStartApproximations: [PerformanceRangeStateResolver.Approximation]
    let transportMetrics: TransportMetrics

    init(
        events: [Event],
        rangeStartApproximations: [PerformanceRangeStateResolver.Approximation] = [],
        transportMetrics: TransportMetrics = .empty
    ) {
        self.events = events
        self.rangeStartApproximations = rangeStartApproximations
        self.transportMetrics = transportMetrics
    }

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
        plan: ScorePerformancePlan,
        guideProjection: [PianoHighlightGuide],
        stepProjection: [PracticeStep],
        tempoMap: MusicXMLTempoMap,
        practiceHandMode: PracticeHandMode,
        activeRange: PracticeActiveRange? = nil,
        transportStartTick: Int? = nil
    ) -> AutoplayPerformanceTimeline {
        var rawEvents: [RawEvent] = []
        rawEvents.reserveCapacity(
            plan.noteEvents.count * 2 + plan.controllerEvents.count + plan.tempoEvents.count
                + guideProjection.count + stepProjection.count + plan.annotations.count
        )

        for (index, guide) in guideProjection.enumerated()
            where activeRange?.contains(tick: guide.tick) ?? true
        {
            rawEvents.append(RawEvent(
                tick: guide.tick,
                priority: 5,
                sourceEventID: nil,
                kind: .advanceGuide(index: index, guideID: guide.id)
            ))
        }

        for (index, step) in stepProjection.enumerated()
            where activeRange?.contains(stepIndex: index) ?? true
        {
            rawEvents.append(RawEvent(
                tick: step.tick,
                priority: 4,
                sourceEventID: nil,
                kind: .advanceStep(index: index)
            ))
        }

        let stateStartTick = transportStartTick ?? activeRange?.tickRange.lowerBound
        let rangeStartState = stateStartTick.map {
            PerformanceRangeStateResolver().resolve(
                plan: plan,
                at: $0,
                practiceHandMode: practiceHandMode
            )
        }
        let rangeEndTick = activeRange?.tickRange.upperBound
        let rangeEndState = rangeEndTick.map {
            PerformanceRangeStateResolver().resolveEnd(plan: plan, at: $0)
        }
        let heldNotes = (rangeStartState?.heldNotes ?? []).map { note in
            PerformanceTransportReducer.Note(
                eventID: note.eventID,
                midiNote: note.midiNote,
                velocity: note.velocity,
                onTick: note.onTick,
                offTick: rangeEndTick.map { min(note.offTick, $0) } ?? note.offTick
            )
        }
        let transportNotes = heldNotes + plan.noteEvents.compactMap { note in
            guard practiceHandMode.allows(hand: note.handAssignment.hand),
                  stateStartTick.map({ note.performedOnTick >= $0 }) ?? true,
                  activeRange?.contains(tick: note.performedOnTick) ?? true
            else {
                return nil
            }
            return PerformanceTransportReducer.Note(
                eventID: note.id,
                midiNote: note.midiNote,
                velocity: note.velocity,
                onTick: note.performedOnTick,
                offTick: max(
                    note.performedOnTick + 1,
                    activeRange.map { min(note.performedOffTick, $0.tickRange.upperBound) }
                        ?? note.performedOffTick
                )
            )
        }
        let transport = PerformanceTransportReducer().reduce(notes: transportNotes)
        for command in transport.commands {
            let kind: EventKind
            let priority: Int
            switch command.kind {
            case .noteOff:
                kind = .noteOff(midi: command.midiNote)
                priority = 1
            case let .noteOn(velocity):
                kind = .noteOn(midi: command.midiNote, velocity: velocity)
                priority = 3
            }
            rawEvents.append(RawEvent(
                tick: command.tick,
                priority: priority,
                sourceEventID: command.eventID.description,
                kind: kind
            ))
        }

        let selectedTempoEvents = (rangeStartState?.tempo.map { [$0] } ?? []) + plan.tempoEvents.filter { event in
            (stateStartTick.map { $0 <= event.tick } ?? true)
                && (activeRange?.contains(tick: event.tick) ?? true)
        }
        for (index, tempo) in selectedTempoEvents.enumerated() {
            rawEvents.append(RawEvent(
                tick: tempo.tick,
                priority: 2,
                sourceEventID: tempo.sourceDirectionID?.description
                    ?? "tempo:\(tempo.performedOccurrenceIndex):\(tempo.tick):\(index)",
                kind: .tempo(
                    quarterBPM: tempo.quarterBPM,
                    endTick: tempo.endTick,
                    endQuarterBPM: tempo.endQuarterBPM
                )
            ))
        }

        let selectedControllerEvents = (rangeStartState?.controllers ?? [])
            + plan.controllerEvents.filter { event in
                (stateStartTick.map { $0 <= event.tick } ?? true)
                    && (activeRange?.contains(tick: event.tick) ?? true)
            }
            + (rangeEndState?.controllerResets ?? [])
        for (index, controller) in selectedControllerEvents.enumerated() {
            rawEvents.append(RawEvent(
                tick: controller.tick,
                priority: 2,
                sourceEventID: controller.sourceDirectionID?.description
                    ?? "controller:\(controller.performedOccurrenceIndex):\(controller.tick):\(index)",
                kind: .controlChange(
                    controller: controller.controllerNumber,
                    value: controller.value
                )
            ))
        }

        // ponytail: priority 0 lets the sole fermata pause hold same-tick note-offs without changing plan note ticks.
        for (index, annotation) in plan.annotations.enumerated() {
            guard annotation.kind == .pause,
                  let durationTicks = annotation.durationTicks,
                  durationTicks > 0,
                  containsAnnotationTick(annotation.tick, activeRange: activeRange)
            else {
                continue
            }
            let seconds = tempoMap.timeSeconds(atTick: annotation.tick + durationTicks)
                - tempoMap.timeSeconds(atTick: annotation.tick)
            guard seconds > 0 else { continue }
            rawEvents.append(RawEvent(
                tick: annotation.tick,
                priority: 0,
                sourceEventID: annotation.sourceDirectionID?.description
                    ?? annotation.provenance.compactMap(\.sourceIdentity).first
                    ?? "annotation:\(annotation.performedOccurrenceIndex):\(annotation.tick):\(index)",
                kind: .pauseSeconds(seconds)
            ))
        }

        let sortedEvents = rawEvents
            .sorted { lhs, rhs in
                if lhs.tick != rhs.tick { return lhs.tick < rhs.tick }
                if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
                let lhsTie = eventTieBreaker(lhs.kind, sourceEventID: lhs.sourceEventID)
                let rhsTie = eventTieBreaker(rhs.kind, sourceEventID: rhs.sourceEventID)
                return lhsTie < rhsTie
            }
            .enumerated()
            .map { offset, event in
                Event(
                    id: offset,
                    sourceEventID: event.sourceEventID,
                    tick: event.tick,
                    kind: event.kind
                )
            }

        return AutoplayPerformanceTimeline(
            events: sortedEvents,
            rangeStartApproximations: rangeStartState?.approximations ?? [],
            transportMetrics: TransportMetrics(
                retriggeredEventCount: transport.retriggeredEventCount,
                preventedStaleOffCount: transport.preventedStaleOffCount,
                orphanOffCount: transport.orphanOffCount
            )
        )
    }

    private static func containsAnnotationTick(_ tick: Int, activeRange: PracticeActiveRange?) -> Bool {
        guard let activeRange else { return true }
        return tick >= activeRange.tickRange.lowerBound && tick <= activeRange.tickRange.upperBound
    }

    private static func eventTieBreaker(_ kind: EventKind, sourceEventID: String?) -> String {
        let identity = sourceEventID ?? ""
        return switch kind {
        case let .noteOff(midi):
            "noteOff-\(midi)-\(identity)"
        case let .controlChange(controller, value):
            "control-\(controller)-\(value)-\(identity)"
        case let .tempo(quarterBPM, endTick, endQuarterBPM):
            "tempo-\(quarterBPM)-\(endTick ?? -1)-\(endQuarterBPM ?? -1)-\(identity)"
        case let .noteOn(midi, velocity):
            "noteOn-\(midi)-\(velocity)-\(identity)"
        case let .advanceStep(index):
            "advanceStep-\(index)"
        case let .advanceGuide(index, guideID):
            "advanceGuide-\(index)-\(guideID)"
        case let .pauseSeconds(seconds):
            "pause-\(seconds)-\(identity)"
        }
    }
}

extension AutoplayPerformanceTimeline {
    func recordTransportDiagnostics(
        using reporter: (any DiagnosticsReporting)?,
        stage: String
    ) {
        let heldCount = rangeStartApproximations.count { approximation in
            if case .reattackedHeldNote = approximation { true } else { false }
        }
        let sustainedCount = rangeStartApproximations.count { approximation in
            if case .reattackedSustainedNote = approximation { true } else { false }
        }
        guard transportMetrics != .empty || heldCount > 0 || sustainedCount > 0 else { return }

        reporter?.recordSystem(
            severity: transportMetrics.orphanOffCount > 0 ? .warning : .info,
            category: .pianoPerformance,
            stage: stage,
            summary: "演奏 transport 已完成事件归约",
            reason: "retriggered=\(transportMetrics.retriggeredEventCount); "
                + "staleOffPrevented=\(transportMetrics.preventedStaleOffCount); "
                + "orphanOff=\(transportMetrics.orphanOffCount); "
                + "heldReconstructed=\(heldCount); sustainedReconstructed=\(sustainedCount)"
        )
    }
}
