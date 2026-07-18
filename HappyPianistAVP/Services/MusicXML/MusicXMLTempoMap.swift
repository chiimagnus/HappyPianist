import Foundation

struct MusicXMLTempoMap {
    static let ticksPerQuarter = 480

    struct TempoRamp: Equatable, Sendable {
        let startTick: Int
        let endTick: Int
        let startQuarterBPM: Double
        let endQuarterBPM: Double
        let scope: MusicXMLEventScope
        let sourceDirectionID: MusicXMLDirectionSourceID?
        let performedOccurrenceIndex: Int

        init(
            startTick: Int,
            endTick: Int,
            startQuarterBPM: Double,
            endQuarterBPM: Double,
            scope: MusicXMLEventScope = MusicXMLEventScope(partID: "P1", staff: nil, voice: nil),
            sourceDirectionID: MusicXMLDirectionSourceID? = nil,
            performedOccurrenceIndex: Int = 0
        ) {
            self.startTick = startTick
            self.endTick = endTick
            self.startQuarterBPM = startQuarterBPM
            self.endQuarterBPM = endQuarterBPM
            self.scope = scope
            self.sourceDirectionID = sourceDirectionID
            self.performedOccurrenceIndex = max(0, performedOccurrenceIndex)
        }
    }

    struct PerformanceEvent: Equatable, Sendable {
        let sourceDirectionID: MusicXMLDirectionSourceID?
        let performedOccurrenceIndex: Int
        let tick: Int
        let quarterBPM: Double
        let endTick: Int?
        let endQuarterBPM: Double?
    }

    private struct Segment {
        let startTick: Int
        let endTick: Int
        let startQuarterBPM: Double
        let endQuarterBPM: Double
        let secondsAtStart: TimeInterval
    }

    private let segments: [Segment]
    private let canonicalPerformanceEvents: [PerformanceEvent]

    init(tempoEvents: [MusicXMLTempoEvent], defaultQuarterBPM: Double = 120) {
        self.init(
            tempoEvents: tempoEvents,
            tempoRamps: [],
            defaultQuarterBPM: defaultQuarterBPM,
            partID: tempoEvents.first?.scope.partID
        )
    }

    init(tempoEvents: [MusicXMLTempoEvent], tempoRamps: [TempoRamp], defaultQuarterBPM: Double = 120) {
        self.init(
            tempoEvents: tempoEvents,
            tempoRamps: tempoRamps,
            defaultQuarterBPM: defaultQuarterBPM,
            partID: tempoEvents.first?.scope.partID
        )
    }

    init(performanceEvents: [ScorePerformanceTempoEvent], defaultQuarterBPM: Double = 120) {
        let fixedEvents = performanceEvents.filter { $0.endTick == nil || $0.endQuarterBPM == nil }
        let explicitTicks = Set(fixedEvents.map(\.tick))
        let partID = performanceEvents.compactMap(\.sourceDirectionID?.partID).first ?? "P1"
        let scope = MusicXMLEventScope(partID: partID, staff: nil, voice: nil)

        var tempoEvents = fixedEvents.map { event in
            var tempoEvent = MusicXMLTempoEvent(
                tick: event.tick,
                quarterBPM: event.quarterBPM,
                scope: scope
            )
            tempoEvent.sourceID = event.sourceDirectionID
            tempoEvent.performedOccurrenceIndex = event.performedOccurrenceIndex
            return tempoEvent
        }
        var tempoRamps: [TempoRamp] = []
        for event in performanceEvents {
            guard let endTick = event.endTick, let endQuarterBPM = event.endQuarterBPM else { continue }
            tempoRamps.append(TempoRamp(
                startTick: event.tick,
                endTick: endTick,
                startQuarterBPM: event.quarterBPM,
                endQuarterBPM: endQuarterBPM,
                scope: scope,
                sourceDirectionID: event.sourceDirectionID,
                performedOccurrenceIndex: event.performedOccurrenceIndex
            ))
            if explicitTicks.contains(event.tick) == false {
                var startEvent = MusicXMLTempoEvent(
                    tick: event.tick,
                    quarterBPM: event.quarterBPM,
                    scope: scope
                )
                startEvent.sourceID = event.sourceDirectionID
                startEvent.performedOccurrenceIndex = event.performedOccurrenceIndex
                tempoEvents.append(startEvent)
            }
            if explicitTicks.contains(endTick) == false {
                var endEvent = MusicXMLTempoEvent(
                    tick: endTick,
                    quarterBPM: endQuarterBPM,
                    scope: scope
                )
                endEvent.sourceID = event.sourceDirectionID
                endEvent.performedOccurrenceIndex = event.performedOccurrenceIndex
                tempoEvents.append(endEvent)
            }
        }

        self.init(
            tempoEvents: tempoEvents,
            tempoRamps: tempoRamps,
            defaultQuarterBPM: defaultQuarterBPM,
            partID: partID
        )
    }

    init(
        tempoEvents: [MusicXMLTempoEvent],
        tempoRamps: [TempoRamp],
        defaultQuarterBPM: Double = 120,
        partID: String?
    ) {
        let effectivePartID = partID ?? tempoEvents.first?.scope.partID ?? "P1"
        let validatedDefault = (defaultQuarterBPM.isFinite && defaultQuarterBPM > 0) ? defaultQuarterBPM : 120

        let validatedEvents = tempoEvents
            .filter {
                $0.scope.partID == effectivePartID
                    && $0.tick >= 0
                    && $0.quarterBPM.isFinite
                    && $0.quarterBPM > 0
            }

        var bestByTick: [Int: MusicXMLTempoEvent] = [:]
        for event in validatedEvents {
            if let existing = bestByTick[event.tick] {
                if Self.prefersTempoEvent(event, over: existing) {
                    bestByTick[event.tick] = event
                }
            } else {
                bestByTick[event.tick] = event
            }
        }

        var bpmByTick: [Int: Double] = Dictionary(
            uniqueKeysWithValues: bestByTick.map { ($0.key, $0.value.quarterBPM) }
        )

        if bpmByTick[0] == nil {
            let firstTick = bpmByTick.keys.min()
            let firstBPM = firstTick.flatMap { bpmByTick[$0] } ?? validatedDefault
            bpmByTick[0] = firstBPM
        }

        let validatedRamps = tempoRamps
            .filter { ramp in
                ramp.startTick >= 0
                    && ramp.endTick > ramp.startTick
                    && ramp.startQuarterBPM.isFinite
                    && ramp.endQuarterBPM.isFinite
                    && ramp.startQuarterBPM > 0
                    && ramp.endQuarterBPM > 0
                    && ramp.scope.partID == effectivePartID
            }
            .sorted { lhs, rhs in
                if lhs.startTick != rhs.startTick { return lhs.startTick < rhs.startTick }
                if lhs.endTick != rhs.endTick { return lhs.endTick < rhs.endTick }
                let lhsSource = lhs.sourceDirectionID?.description ?? ""
                let rhsSource = rhs.sourceDirectionID?.description ?? ""
                if lhsSource != rhsSource { return lhsSource < rhsSource }
                return lhs.performedOccurrenceIndex < rhs.performedOccurrenceIndex
            }

        var performanceEvents = bestByTick.values.map { event in
            PerformanceEvent(
                sourceDirectionID: event.sourceID,
                performedOccurrenceIndex: event.performedOccurrenceIndex,
                tick: event.tick,
                quarterBPM: event.quarterBPM,
                endTick: nil,
                endQuarterBPM: nil
            )
        }
        if bestByTick[0] == nil {
            performanceEvents.append(PerformanceEvent(
                sourceDirectionID: nil,
                performedOccurrenceIndex: 0,
                tick: 0,
                quarterBPM: bpmByTick[0] ?? validatedDefault,
                endTick: nil,
                endQuarterBPM: nil
            ))
        }
        performanceEvents.append(contentsOf: validatedRamps.map { ramp in
            PerformanceEvent(
                sourceDirectionID: ramp.sourceDirectionID,
                performedOccurrenceIndex: ramp.performedOccurrenceIndex,
                tick: ramp.startTick,
                quarterBPM: ramp.startQuarterBPM,
                endTick: ramp.endTick,
                endQuarterBPM: ramp.endQuarterBPM
            )
        })
        canonicalPerformanceEvents = performanceEvents.sorted(by: Self.performanceEventOrder)

        let breakpoints = Self.makeBreakpoints(bpmByTick: bpmByTick, ramps: validatedRamps)
        let sortedTempoTicks = bpmByTick.keys.sorted()
        let baselineBPMAtTick: (Int) -> Double = { tick in
            let clamped = max(0, tick)
            guard sortedTempoTicks.isEmpty == false else { return validatedDefault }

            var low = 0
            var high = sortedTempoTicks.count - 1
            var bestIndex = -1

            while low <= high {
                let mid = (low + high) / 2
                if sortedTempoTicks[mid] <= clamped {
                    bestIndex = mid
                    low = mid + 1
                } else {
                    high = mid - 1
                }
            }

            guard bestIndex >= 0 else { return validatedDefault }
            return bpmByTick[sortedTempoTicks[bestIndex]] ?? validatedDefault
        }

        var built: [Segment] = []
        built.reserveCapacity(max(1, breakpoints.count))

        var seconds: TimeInterval = 0
        for i in 0 ..< max(0, breakpoints.count - 1) {
            let startTick = breakpoints[i]
            let endTick = breakpoints[i + 1]
            guard endTick > startTick else { continue }

            if let activeRamp = Self.activeRamp(atTick: startTick, ramps: validatedRamps) {
                let startBPM = Self.interpolateBPM(ramp: activeRamp, tick: startTick)
                let endBPM = Self.interpolateBPM(ramp: activeRamp, tick: endTick)
                built.append(
                    Segment(
                        startTick: startTick,
                        endTick: endTick,
                        startQuarterBPM: startBPM,
                        endQuarterBPM: endBPM,
                        secondsAtStart: seconds
                    )
                )
                seconds += Self.secondsForLinearTempoSegment(
                    startTick: startTick,
                    endTick: endTick,
                    startQuarterBPM: startBPM,
                    endQuarterBPM: endBPM
                )
            } else {
                let bpm = baselineBPMAtTick(startTick)
                built.append(
                    Segment(
                        startTick: startTick,
                        endTick: endTick,
                        startQuarterBPM: bpm,
                        endQuarterBPM: bpm,
                        secondsAtStart: seconds
                    )
                )
                seconds += Self.secondsForLinearTempoSegment(
                    startTick: startTick,
                    endTick: endTick,
                    startQuarterBPM: bpm,
                    endQuarterBPM: bpm
                )
            }
        }

        let lastTick = breakpoints.last ?? 0
        let lastBPM = baselineBPMAtTick(lastTick)
        built.append(
            Segment(
                startTick: lastTick,
                endTick: Int.max,
                startQuarterBPM: lastBPM,
                endQuarterBPM: lastBPM,
                secondsAtStart: seconds
            )
        )

        segments = built
    }

    func performanceEvents() -> [PerformanceEvent] {
        canonicalPerformanceEvents
    }

    func timeSeconds(atTick tick: Int) -> TimeInterval {
        let clampedTick = max(0, tick)
        guard let index = segmentIndex(atOrBeforeTick: clampedTick) else { return 0 }

        let segment = segments[index]
        let endTick = min(clampedTick, segment.endTick)
        return segment.secondsAtStart + Self.secondsForLinearTempoSegment(
            startTick: segment.startTick,
            endTick: endTick,
            startQuarterBPM: segment.startQuarterBPM,
            endQuarterBPM: segment.endQuarterBPM
        )
    }

    func quarterBPM(atTick tick: Int) -> Double {
        let clampedTick = max(0, tick)
        guard let index = segmentIndex(atOrBeforeTick: clampedTick) else { return 120 }
        let segment = segments[index]
        guard segment.endTick != Int.max, segment.endTick > segment.startTick else {
            return segment.startQuarterBPM
        }
        let boundedTick = min(clampedTick, segment.endTick)
        let fraction = Double(boundedTick - segment.startTick)
            / Double(segment.endTick - segment.startTick)
        return segment.startQuarterBPM
            + (segment.endQuarterBPM - segment.startQuarterBPM) * fraction
    }

    func durationSeconds(fromTick: Int, toTick: Int) -> TimeInterval {
        let start = max(0, fromTick)
        let end = max(0, toTick)
        guard end > start else { return 0 }
        return max(0, timeSeconds(atTick: end) - timeSeconds(atTick: start))
    }

    private func segmentIndex(atOrBeforeTick tick: Int) -> Int? {
        guard segments.isEmpty == false else { return nil }

        var low = 0
        var high = segments.count - 1
        var best = -1

        while low <= high {
            let mid = (low + high) / 2
            if segments[mid].startTick <= tick {
                best = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        return best >= 0 ? best : nil
    }

    private static func secondsForLinearTempoSegment(
        startTick: Int,
        endTick: Int,
        startQuarterBPM: Double,
        endQuarterBPM: Double
    ) -> TimeInterval {
        let start = max(0, startTick)
        let end = max(start, endTick)
        let deltaTicks = end - start
        guard deltaTicks > 0 else { return 0 }

        let bpm0 = max(0.000_1, startQuarterBPM)
        let bpm1 = max(0.000_1, endQuarterBPM)

        let coeff = 60.0 / Double(ticksPerQuarter)
        let slopePerTick = (bpm1 - bpm0) / Double(max(1, endTick - startTick))

        if abs(slopePerTick) < 1e-12 {
            return coeff * (Double(deltaTicks) / bpm0)
        }

        let a = bpm0 - slopePerTick * Double(startTick)
        let t0 = Double(start)
        let t1 = Double(end)
        let denom0 = max(0.000_1, a + slopePerTick * t0)
        let denom1 = max(0.000_1, a + slopePerTick * t1)
        return coeff * (log(denom1 / denom0) / slopePerTick)
    }

    private static func makeBreakpoints(bpmByTick: [Int: Double], ramps: [TempoRamp]) -> [Int] {
        var ticks = Set(bpmByTick.keys.map { max(0, $0) })
        ticks.insert(0)
        for ramp in ramps {
            ticks.insert(max(0, ramp.startTick))
            ticks.insert(max(0, ramp.endTick))
        }
        let sorted = ticks.sorted()
        return sorted.isEmpty ? [0] : sorted
    }

    private static func activeRamp(atTick tick: Int, ramps: [TempoRamp]) -> TempoRamp? {
        ramps
            .filter { $0.startTick <= tick && tick < $0.endTick }
            .max { lhs, rhs in
                if lhs.startTick != rhs.startTick { return lhs.startTick < rhs.startTick }
                return lhs.endTick < rhs.endTick
            }
    }

    private static func interpolateBPM(ramp: TempoRamp, tick: Int) -> Double {
        let start = Double(ramp.startTick)
        let end = Double(ramp.endTick)
        let t = min(max(Double(tick), start), end)
        let fraction = (t - start) / max(1.0, end - start)
        return ramp.startQuarterBPM + (ramp.endQuarterBPM - ramp.startQuarterBPM) * fraction
    }

    private static func prefersTempoEvent(_ candidate: MusicXMLTempoEvent, over existing: MusicXMLTempoEvent) -> Bool {
        switch (candidate.scope.staff, existing.scope.staff) {
        case (nil, .some):
            return true
        case (.some, nil):
            return false
        case let (.some(candidateStaff), .some(existingStaff)) where candidateStaff != existingStaff:
            return candidateStaff < existingStaff
        default:
            if (candidate.sourceID == nil) != (existing.sourceID == nil) {
                return candidate.sourceID != nil
            }
            let candidateSource = candidate.sourceID?.description ?? ""
            let existingSource = existing.sourceID?.description ?? ""
            if candidateSource != existingSource { return candidateSource < existingSource }
            if candidate.performedOccurrenceIndex != existing.performedOccurrenceIndex {
                return candidate.performedOccurrenceIndex < existing.performedOccurrenceIndex
            }
            return candidate.quarterBPM < existing.quarterBPM
        }
    }

    private static func performanceEventOrder(_ lhs: PerformanceEvent, _ rhs: PerformanceEvent) -> Bool {
        if lhs.tick != rhs.tick { return lhs.tick < rhs.tick }
        if (lhs.endTick == nil) != (rhs.endTick == nil) { return lhs.endTick == nil }
        if lhs.quarterBPM != rhs.quarterBPM { return lhs.quarterBPM < rhs.quarterBPM }
        let lhsSource = lhs.sourceDirectionID?.description ?? ""
        let rhsSource = rhs.sourceDirectionID?.description ?? ""
        if lhsSource != rhsSource { return lhsSource < rhsSource }
        return lhs.performedOccurrenceIndex < rhs.performedOccurrenceIndex
    }
}
