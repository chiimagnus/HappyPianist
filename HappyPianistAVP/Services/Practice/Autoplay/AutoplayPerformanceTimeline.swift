import Foundation

struct AutoplayPerformanceTimeline: Equatable, Sendable {
    struct TransportMetrics: Equatable, Sendable {
        static let empty = TransportMetrics(
            retriggeredEventCount: 0,
            preventedStaleOffCount: 0,
            orphanOffCount: 0
        )

        let retriggeredEventCount: Int
        let preventedStaleOffCount: Int
        let orphanOffCount: Int
    }

    enum EventKind: Equatable, Sendable {
        case pauseSeconds(TimeInterval)
        case noteOff(midi: Int)
        case controlChange(controller: UInt8, value: UInt8)
        case tempo(quarterBPM: Double, endTick: Int?, endQuarterBPM: Double?)
        case noteOn(midi: Int, velocity: UInt8)
        case advanceStep(index: Int)
        case advanceGuide(index: Int, guideID: Int)
    }

    struct Event: Equatable, Identifiable, Sendable {
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

    private struct BuildGuide: Sendable {
        let index: Int
        let id: Int
        let tick: Int
    }

    private struct BuildStep: Sendable {
        let index: Int
        let tick: Int
    }

    private struct ActiveRangeSnapshot: Sendable {
        let stepRange: Range<Int>
        let tickRange: Range<Int>

        func contains(stepIndex: Int) -> Bool {
            stepRange.contains(stepIndex)
        }

        func contains(tick: Int) -> Bool {
            tickRange.contains(tick)
        }
    }

    private struct BuildInput: Sendable {
        let plan: ScorePerformancePlan
        let guides: [BuildGuide]
        let steps: [BuildStep]
        let tempoMap: MusicXMLTempoMap
        let practiceHandMode: PracticeHandMode
        let activeRange: ActiveRangeSnapshot?
        let transportStartTick: Int?
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
        build(input: makeBuildInput(
            plan: plan,
            guideProjection: guideProjection,
            stepProjection: stepProjection,
            tempoMap: tempoMap,
            practiceHandMode: practiceHandMode,
            activeRange: activeRange,
            transportStartTick: transportStartTick
        ))
    }

    @MainActor
    static func buildOffMain(
        plan: ScorePerformancePlan,
        guideProjection: [PianoHighlightGuide],
        stepProjection: [PracticeStep],
        tempoMap: MusicXMLTempoMap,
        practiceHandMode: PracticeHandMode,
        activeRange: PracticeActiveRange? = nil,
        transportStartTick: Int? = nil
    ) async -> AutoplayPerformanceTimeline {
        let input = makeBuildInput(
            plan: plan,
            guideProjection: guideProjection,
            stepProjection: stepProjection,
            tempoMap: tempoMap,
            practiceHandMode: practiceHandMode,
            activeRange: activeRange,
            transportStartTick: transportStartTick
        )
        let task = Task.detached(priority: .userInitiated) {
            build(input: input)
        }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private static func makeBuildInput(
        plan: ScorePerformancePlan,
        guideProjection: [PianoHighlightGuide],
        stepProjection: [PracticeStep],
        tempoMap: MusicXMLTempoMap,
        practiceHandMode: PracticeHandMode,
        activeRange: PracticeActiveRange?,
        transportStartTick: Int?
    ) -> BuildInput {
        BuildInput(
            plan: plan,
            guides: guideProjection.enumerated().map { index, guide in
                BuildGuide(index: index, id: guide.id, tick: guide.tick)
            },
            steps: stepProjection.enumerated().map { index, step in
                BuildStep(index: index, tick: step.tick)
            },
            tempoMap: tempoMap,
            practiceHandMode: practiceHandMode,
            activeRange: activeRange.map {
                ActiveRangeSnapshot(stepRange: $0.stepRange, tickRange: $0.tickRange)
            },
            transportStartTick: transportStartTick
        )
    }

    private static func build(input: BuildInput) -> AutoplayPerformanceTimeline {
        let plan = input.plan
        let guideProjection = input.guides
        let stepProjection = input.steps
        let tempoMap = input.tempoMap
        let practiceHandMode = input.practiceHandMode
        let activeRange = input.activeRange
        let transportStartTick = input.transportStartTick
        var rawEvents: [RawEvent] = []
        rawEvents.reserveCapacity(
            plan.noteEvents.count * 2 + plan.controllerEvents.count + plan.tempoEvents.count
                + guideProjection.count + stepProjection.count + plan.annotations.count
        )

        for guide in guideProjection
            where activeRange?.contains(tick: guide.tick) ?? true
        {
            rawEvents.append(RawEvent(
                tick: guide.tick,
                priority: 5,
                sourceEventID: nil,
                kind: .advanceGuide(index: guide.index, guideID: guide.id)
            ))
        }

        for step in stepProjection
            where activeRange?.contains(stepIndex: step.index) ?? true
        {
            rawEvents.append(RawEvent(
                tick: step.tick,
                priority: 4,
                sourceEventID: nil,
                kind: .advanceStep(index: step.index)
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
            .enumerated()
            .sorted { lhs, rhs in
                if lhs.element.tick != rhs.element.tick {
                    return lhs.element.tick < rhs.element.tick
                }
                if lhs.element.priority != rhs.element.priority {
                    return lhs.element.priority < rhs.element.priority
                }
                return lhs.offset < rhs.offset
            }
            .enumerated()
            .map { offset, indexedEvent in
                let event = indexedEvent.element
                return Event(
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

    private static func containsAnnotationTick(_ tick: Int, activeRange: ActiveRangeSnapshot?) -> Bool {
        guard let activeRange else { return true }
        return tick >= activeRange.tickRange.lowerBound && tick <= activeRange.tickRange.upperBound
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
