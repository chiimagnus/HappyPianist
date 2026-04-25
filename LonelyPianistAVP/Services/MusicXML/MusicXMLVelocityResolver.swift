import Foundation

struct MusicXMLVelocityResolver {
    private struct WedgeSpan: Equatable {
        let startTick: Int
        let endTick: Int
        let kind: MusicXMLWedgeKind
        let numberToken: String?
        let scope: MusicXMLEventScope
    }

    let dynamicEvents: [MusicXMLDynamicEvent]
    let wedgeEvents: [MusicXMLWedgeEvent]
    let wedgeEnabled: Bool
    let defaultVelocity: UInt8
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
        wedgeSpans = Self.buildWedgeSpans(from: wedgeEvents)
    }

    func velocity(for note: MusicXMLNoteEvent) -> UInt8 {
        if let override = note.dynamicsOverrideVelocity {
            return override
        }

        let noteStaff = note.staff ?? 1

        let baseVelocity: UInt8 = if wedgeEnabled,
                                     let velocity = wedgeVelocity(
                                         partID: note.partID,
                                         tick: note.tick,
                                         staff: noteStaff
                                     )
        {
            velocity
        } else {
            resolvedVelocityFromDynamics(partID: note.partID, tick: note.tick, staff: noteStaff) ?? defaultVelocity
        }

        return applyArticulations(note: note, velocity: baseVelocity)
    }

    private func applyArticulations(note: MusicXMLNoteEvent, velocity: UInt8) -> UInt8 {
        var value = Int(velocity)
        if note.articulations.contains(.accent) {
            value += 10
        }
        if note.articulations.contains(.marcato) {
            value += 15
        }
        return UInt8(min(127, max(0, value)))
    }

    private func resolvedVelocityFromDynamics(partID: String, tick: Int, staff: Int) -> UInt8? {
        resolvedVelocity(source: .soundDynamicsAttribute, partID: partID, tick: tick, staff: staff)
            ?? resolvedVelocity(source: .directionDynamics, partID: partID, tick: tick, staff: staff)
    }

    private func resolvedVelocity(
        source: MusicXMLDynamicEventSource,
        partID: String,
        tick: Int,
        staff: Int
    ) -> UInt8? {
        if let staffSpecific = dynamicEvents
            .reversed()
            .first(where: { event in
                event.source == source &&
                    event.scope.partID == partID &&
                    event.tick <= tick &&
                    event.scope.staff == staff
            })
        {
            return staffSpecific.velocity
        }

        if let global = dynamicEvents
            .reversed()
            .first(where: { event in
                event.source == source &&
                    event.scope.partID == partID &&
                    event.tick <= tick &&
                    event.scope.staff == nil
            })
        {
            return global.velocity
        }

        return nil
    }

    private func wedgeVelocity(partID: String, tick: Int, staff: Int) -> UInt8? {
        guard wedgeSpans.isEmpty == false else { return nil }

        let candidates = wedgeSpans.filter { span in
            span.scope.partID == partID &&
                span.startTick <= tick &&
                tick <= span.endTick
        }
        guard candidates.isEmpty == false else { return nil }

        let staffSpecific = candidates
            .filter { $0.scope.staff == staff }
            .max(by: { $0.startTick < $1.startTick })

        let global = candidates
            .filter { $0.scope.staff == nil }
            .max(by: { $0.startTick < $1.startTick })

        let span = staffSpecific ?? global
        guard let span else { return nil }
        guard span.endTick > span.startTick else { return nil }
        guard span.kind != .stop else { return nil }

        let startVelocity = resolvedVelocityFromDynamics(partID: partID, tick: span.startTick, staff: staff) ??
            defaultVelocity
        guard let endVelocity = firstExplicitDynamicVelocity(atOrAfterTick: span.endTick, partID: partID, staff: staff)
        else {
            return nil
        }

        let progress = Double(tick - span.startTick) / Double(span.endTick - span.startTick)
        let interpolated = Double(startVelocity) + (Double(endVelocity) - Double(startVelocity)) * progress
        let clamped = min(127, max(0, Int(interpolated.rounded())))
        return UInt8(clamped)
    }

    private func firstExplicitDynamicVelocity(atOrAfterTick tick: Int, partID: String, staff: Int) -> UInt8? {
        if let staffSpecific = dynamicEvents.first(where: { event in
            event.scope.partID == partID &&
                event.tick >= tick &&
                event.scope.staff == staff
        }) {
            return staffSpecific.velocity
        }

        if let global = dynamicEvents.first(where: { event in
            event.scope.partID == partID &&
                event.tick >= tick &&
                event.scope.staff == nil
        }) {
            return global.velocity
        }

        return nil
    }

    private static func buildWedgeSpans(from wedgeEvents: [MusicXMLWedgeEvent]) -> [WedgeSpan] {
        var active: [String: (startTick: Int, kind: MusicXMLWedgeKind, scope: MusicXMLEventScope)] = [:]
        var spans: [WedgeSpan] = []
        spans.reserveCapacity(wedgeEvents.count / 2)

        for event in wedgeEvents {
            let number = event.numberToken ?? ""
            let staffKey = event.scope.staff.map(String.init) ?? "_"
            let key = "\(event.scope.partID)-\(staffKey)-\(number)"

            switch event.kind {
                case .crescendoStart, .diminuendoStart:
                    active[key] = (startTick: event.tick, kind: event.kind, scope: event.scope)
                case .stop:
                    if let start = active[key] {
                        spans.append(
                            WedgeSpan(
                                startTick: start.startTick,
                                endTick: event.tick,
                                kind: start.kind,
                                numberToken: event.numberToken,
                                scope: start.scope
                            )
                        )
                        active[key] = nil
                    }
            }
        }

        return spans
    }
}
