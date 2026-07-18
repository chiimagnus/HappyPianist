import Foundation

struct MusicXMLVelocityResolver {
    struct WedgeSpan: Equatable {
        let start: MusicXMLWedgeEvent
        let stop: MusicXMLWedgeEvent
    }

    let dynamicEvents: [MusicXMLDynamicEvent]
    let wedgeEvents: [MusicXMLWedgeEvent]
    let wedgeEnabled: Bool
    let defaultVelocity: UInt8
    let dynamicCurves: [MusicXMLDynamicCurve]
    let wedgeApproximations: [MusicXMLWedgeApproximation]
    private let wedgeSpans: [WedgeSpan]

    init(
        dynamicEvents: [MusicXMLDynamicEvent],
        wedgeEvents: [MusicXMLWedgeEvent] = [],
        wedgeEnabled: Bool = false,
        defaultVelocity: UInt8 = 96
    ) {
        self.dynamicEvents = dynamicEvents
        self.wedgeEvents = wedgeEvents
        self.wedgeEnabled = wedgeEnabled
        self.defaultVelocity = defaultVelocity

        let pairing = Self.buildWedgeSpans(from: wedgeEvents)
        wedgeSpans = pairing.spans
        let curveBuild = Self.buildDynamicCurves(
            spans: pairing.spans,
            dynamicEvents: dynamicEvents,
            defaultVelocity: defaultVelocity
        )
        dynamicCurves = curveBuild.curves
        wedgeApproximations = pairing.approximations + curveBuild.approximations
    }

    func velocity(for note: MusicXMLNoteEvent) -> UInt8 {
        resolution(for: note).velocity
    }

    func resolution(for note: MusicXMLNoteEvent) -> MusicXMLVelocityResolution {
        let baseVelocity: Int
        let selectedCurve: MusicXMLDynamicCurve?
        let curveVelocity: Double?

        if let override = note.dynamicsOverrideVelocity {
            baseVelocity = Int(override)
            selectedCurve = nil
            curveVelocity = nil
        } else {
            baseVelocity = Int(
                resolvedDynamicEvent(
                    partID: note.partID,
                    tick: note.tick,
                    staff: note.staff,
                    voice: note.voice
                )?.velocity ?? defaultVelocity
            )
            selectedCurve = wedgeEnabled ? curve(
                partID: note.partID,
                tick: note.tick,
                staff: note.staff,
                voice: note.voice
            ) : nil
            curveVelocity = selectedCurve?.interpolatedVelocity(at: note.tick)
        }

        let articulationDelta = articulationDelta(for: note)
        let resolvedBase = Int((curveVelocity ?? Double(baseVelocity)).rounded())
        let unclampedVelocity = resolvedBase + articulationDelta
        let output = UInt8(min(127, max(0, unclampedVelocity)))

        return MusicXMLVelocityResolution(
            baseVelocity: baseVelocity,
            curveVelocity: curveVelocity,
            articulationDelta: articulationDelta,
            unclampedVelocity: unclampedVelocity,
            velocity: output,
            curve: selectedCurve
        )
    }

    private func articulationDelta(for note: MusicXMLNoteEvent) -> Int {
        var value = 0
        if note.articulations.contains(.accent) {
            value += 10
        }
        if note.articulations.contains(.marcato) {
            value += 15
        }
        return value
    }

    private func resolvedDynamicEvent(
        partID: String,
        tick: Int,
        staff: Int?,
        voice: Int?
    ) -> MusicXMLDynamicEvent? {
        Self.latestDynamicEvent(
            in: dynamicEvents,
            partID: partID,
            atOrBeforeTick: tick,
            staff: staff,
            voice: voice
        )
    }

    private func curve(
        partID: String,
        tick: Int,
        staff: Int?,
        voice: Int?
    ) -> MusicXMLDynamicCurve? {
        dynamicCurves
            .filter { curve in
                curve.scope.partID == partID
                    && curve.startTick <= tick
                    && tick <= curve.endTick
                    && Self.scope(curve.scope, matchesStaff: staff, voice: voice)
            }
            .max(by: { lhs, rhs in
                if lhs.startTick != rhs.startTick { return lhs.startTick < rhs.startTick }
                let lhsSpecificity = Self.scopeSpecificity(lhs.scope, staff: staff, voice: voice)
                let rhsSpecificity = Self.scopeSpecificity(rhs.scope, staff: staff, voice: voice)
                if lhsSpecificity != rhsSpecificity { return lhsSpecificity < rhsSpecificity }
                return lhs.numberToken < rhs.numberToken
            })
    }

    private static func buildDynamicCurves(
        spans: [WedgeSpan],
        dynamicEvents: [MusicXMLDynamicEvent],
        defaultVelocity: UInt8
    ) -> (curves: [MusicXMLDynamicCurve], approximations: [MusicXMLWedgeApproximation]) {
        var curves: [MusicXMLDynamicCurve] = []
        var approximations: [MusicXMLWedgeApproximation] = []

        for span in spans {
            guard span.stop.tick > span.start.tick else {
                approximations.append(MusicXMLWedgeApproximation(
                    sourceID: span.start.sourceID,
                    reason: "wedge-zero-duration"
                ))
                continue
            }

            let startEvent = latestDynamicEvent(
                in: dynamicEvents,
                partID: span.start.scope.partID,
                atOrBeforeTick: span.start.tick,
                staff: span.start.scope.staff,
                voice: span.start.scope.voice
            )
            guard let targetEvent = firstDynamicEvent(
                in: dynamicEvents,
                partID: span.start.scope.partID,
                atOrAfterTick: span.stop.tick,
                staff: span.start.scope.staff,
                voice: span.start.scope.voice
            ) else {
                approximations.append(MusicXMLWedgeApproximation(
                    sourceID: span.start.sourceID,
                    reason: "wedge-missing-target-dynamic"
                ))
                continue
            }

            let startVelocity = Int(startEvent?.velocity ?? defaultVelocity)
            let endVelocity = Int(targetEvent.velocity)
            let directionConflicts = switch span.start.kind {
            case .crescendoStart:
                endVelocity < startVelocity
            case .diminuendoStart:
                endVelocity > startVelocity
            case .stop:
                false
            }
            if directionConflicts {
                approximations.append(MusicXMLWedgeApproximation(
                    sourceID: span.start.sourceID,
                    reason: "wedge-direction-conflicts-with-target"
                ))
            }

            curves.append(MusicXMLDynamicCurve(
                startTick: span.start.tick,
                endTick: span.stop.tick,
                startVelocity: startVelocity,
                endVelocity: endVelocity,
                scope: span.start.scope,
                numberToken: span.start.normalizedNumberToken,
                kind: span.start.kind,
                provenance: .explicitWedge(
                    startSourceID: span.start.sourceID,
                    stopSourceID: span.stop.sourceID,
                    targetSourceID: targetEvent.sourceID
                )
            ))
        }

        return (
            curves: curves.sorted { lhs, rhs in
                if lhs.startTick != rhs.startTick { return lhs.startTick < rhs.startTick }
                if lhs.endTick != rhs.endTick { return lhs.endTick < rhs.endTick }
                return lhs.numberToken < rhs.numberToken
            },
            approximations: approximations
        )
    }

    private static func latestDynamicEvent(
        in dynamicEvents: [MusicXMLDynamicEvent],
        partID: String,
        atOrBeforeTick tick: Int,
        staff: Int?,
        voice: Int?
    ) -> MusicXMLDynamicEvent? {
        dynamicEvents
            .filter { event in
                event.scope.partID == partID
                    && event.tick <= tick
                    && scope(event.scope, matchesStaff: staff, voice: voice)
            }
            .max(by: { lhs, rhs in
                compareDynamicEvents(lhs, rhs, staff: staff, voice: voice)
            })
    }

    private static func firstDynamicEvent(
        in dynamicEvents: [MusicXMLDynamicEvent],
        partID: String,
        atOrAfterTick tick: Int,
        staff: Int?,
        voice: Int?
    ) -> MusicXMLDynamicEvent? {
        dynamicEvents
            .filter { event in
                event.scope.partID == partID
                    && event.tick >= tick
                    && scope(event.scope, matchesStaff: staff, voice: voice)
            }
            .min(by: { lhs, rhs in
                if lhs.tick != rhs.tick { return lhs.tick < rhs.tick }
                let lhsSpecificity = scopeSpecificity(lhs.scope, staff: staff, voice: voice)
                let rhsSpecificity = scopeSpecificity(rhs.scope, staff: staff, voice: voice)
                if lhsSpecificity != rhsSpecificity { return lhsSpecificity > rhsSpecificity }
                let lhsSource = sourcePrecedence(lhs.source)
                let rhsSource = sourcePrecedence(rhs.source)
                if lhsSource != rhsSource { return lhsSource > rhsSource }
                let lhsIdentity = lhs.sourceID?.description ?? ""
                let rhsIdentity = rhs.sourceID?.description ?? ""
                if lhsIdentity != rhsIdentity { return lhsIdentity < rhsIdentity }
                return lhs.velocity > rhs.velocity
            })
    }

    private static func compareDynamicEvents(
        _ lhs: MusicXMLDynamicEvent,
        _ rhs: MusicXMLDynamicEvent,
        staff: Int?,
        voice: Int?
    ) -> Bool {
        if lhs.tick != rhs.tick { return lhs.tick < rhs.tick }
        let lhsSpecificity = scopeSpecificity(lhs.scope, staff: staff, voice: voice)
        let rhsSpecificity = scopeSpecificity(rhs.scope, staff: staff, voice: voice)
        if lhsSpecificity != rhsSpecificity { return lhsSpecificity < rhsSpecificity }
        let lhsSource = sourcePrecedence(lhs.source)
        let rhsSource = sourcePrecedence(rhs.source)
        if lhsSource != rhsSource { return lhsSource < rhsSource }
        let lhsIdentity = lhs.sourceID?.description ?? ""
        let rhsIdentity = rhs.sourceID?.description ?? ""
        if lhsIdentity != rhsIdentity { return lhsIdentity < rhsIdentity }
        return lhs.velocity < rhs.velocity
    }

    private static func scope(_ scope: MusicXMLEventScope, matchesStaff staff: Int?, voice: Int?) -> Bool {
        (scope.staff == nil || scope.staff == staff)
            && (scope.voice == nil || scope.voice == voice)
    }

    private static func scopeSpecificity(_ scope: MusicXMLEventScope, staff: Int?, voice: Int?) -> Int {
        var value = 0
        if scope.staff != nil, scope.staff == staff { value += 1 }
        if scope.voice != nil, scope.voice == voice { value += 2 }
        return value
    }

    private static func sourcePrecedence(_ source: MusicXMLDynamicEventSource) -> Int {
        switch source {
        case .directionDynamics:
            0
        case .soundDynamicsAttribute:
            1
        }
    }

    private static func buildWedgeSpans(
        from wedgeEvents: [MusicXMLWedgeEvent]
    ) -> (spans: [WedgeSpan], approximations: [MusicXMLWedgeApproximation]) {
        let orderedEvents = wedgeEvents.sorted { lhs, rhs in
            if lhs.tick != rhs.tick { return lhs.tick < rhs.tick }
            let lhsKind = kindOrder(lhs.kind)
            let rhsKind = kindOrder(rhs.kind)
            if lhsKind != rhsKind { return lhsKind < rhsKind }
            return (lhs.sourceID?.description ?? "") < (rhs.sourceID?.description ?? "")
        }
        var active: [MusicXMLWedgePairKey: MusicXMLWedgeEvent] = [:]
        var spans: [WedgeSpan] = []
        var approximations: [MusicXMLWedgeApproximation] = []

        for event in orderedEvents {
            switch event.kind {
            case .crescendoStart, .diminuendoStart:
                if let replaced = active.updateValue(event, forKey: event.pairKey) {
                    approximations.append(MusicXMLWedgeApproximation(
                        sourceID: replaced.sourceID,
                        reason: "wedge-start-replaced-before-stop"
                    ))
                }
            case .stop:
                guard let start = active.removeValue(forKey: event.pairKey) else {
                    approximations.append(MusicXMLWedgeApproximation(
                        sourceID: event.sourceID,
                        reason: "wedge-stop-without-start"
                    ))
                    continue
                }
                spans.append(WedgeSpan(start: start, stop: event))
            }
        }

        for event in active.values.sorted(by: { $0.tick < $1.tick }) {
            approximations.append(MusicXMLWedgeApproximation(
                sourceID: event.sourceID,
                reason: "wedge-start-without-stop"
            ))
        }
        return (spans: spans, approximations: approximations)
    }

    private static func kindOrder(_ kind: MusicXMLWedgeKind) -> Int {
        switch kind {
        case .crescendoStart, .diminuendoStart:
            0
        case .stop:
            1
        }
    }
}
