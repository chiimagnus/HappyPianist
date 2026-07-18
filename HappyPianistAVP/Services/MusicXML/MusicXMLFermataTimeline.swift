import Foundation

struct MusicXMLFermataTimeline: Equatable {
    private struct Hold: Equatable {
        let tick: Int
        let staff: Int?
        let extraTicks: Int
        let interpretationProfileID: String
    }

    private let holds: [Hold]
    let interpretationProfileID: String

    init(
        fermataEvents: [MusicXMLFermataEvent],
        notes: [MusicXMLNoteEvent],
        interpretationProfile: MusicXMLInterpretationProfile = .generic
    ) {
        interpretationProfileID = interpretationProfile.id
        let durationByTickAndStaff = Self.makeDurationByTickAndStaff(notes: notes)
        let durationByTickAnyStaff = Self.makeDurationByTickAnyStaff(durationByTickAndStaff)
        var extraTicksByKey: [String: Int] = [:]

        for event in fermataEvents {
            let staff = event.scope.staff
            let durationTicks = if let staff {
                durationByTickAndStaff[Self.keyForDuration(tick: event.tick, staff: staff)]
            } else {
                durationByTickAnyStaff[event.tick]
            }
            let baseDuration = max(1, durationTicks ?? MusicXMLTempoMap.ticksPerQuarter)
            let extraTicks = interpretationProfile.fermataExtraTicks(forBaseDurationTicks: baseDuration)
            let key = Self.keyForHold(tick: event.tick, staff: staff)
            extraTicksByKey[key] = max(extraTicksByKey[key] ?? 0, extraTicks)
        }

        holds = extraTicksByKey.map { entry in
            let parts = entry.key.split(separator: ":", omittingEmptySubsequences: false)
            let tick = Int(parts.first ?? "") ?? 0
            let staff = parts.count >= 2 ? Int(parts[1]) : nil
            return Hold(
                tick: tick,
                staff: staff,
                extraTicks: entry.value,
                interpretationProfileID: interpretationProfile.id
            )
        }.sorted { lhs, rhs in
            if lhs.tick != rhs.tick { return lhs.tick < rhs.tick }
            return (lhs.staff ?? -1) < (rhs.staff ?? -1)
        }
    }

    func extraHoldSeconds(atTick tick: Int, staffs: Set<Int>, tempoMap: MusicXMLTempoMap) -> TimeInterval {
        let extraTicks = matchingExtraTicks(atTick: tick, staffs: staffs)
        guard extraTicks > 0 else { return 0 }
        return tempoMap.durationSeconds(fromTick: tick, toTick: tick + extraTicks)
    }

    func extraTicksForNote(atTick tick: Int, staff: Int) -> Int {
        matchingExtraTicks(atTick: tick, staffs: [staff])
    }

    private func matchingExtraTicks(atTick tick: Int, staffs: Set<Int>) -> Int {
        holds
            .filter { $0.tick == tick && ($0.staff == nil || staffs.contains($0.staff ?? -1)) }
            .map(\.extraTicks)
            .max() ?? 0
    }

    private static func makeDurationByTickAndStaff(notes: [MusicXMLNoteEvent]) -> [String: Int] {
        var result: [String: Int] = [:]
        for note in notes where note.isRest == false {
            let staff = note.staff ?? 1
            let key = keyForDuration(tick: note.tick, staff: staff)
            result[key] = max(result[key] ?? 0, max(0, note.durationTicks))
        }
        return result
    }

    private static func makeDurationByTickAnyStaff(_ durationByTickAndStaff: [String: Int]) -> [Int: Int] {
        var result: [Int: Int] = [:]
        for (key, duration) in durationByTickAndStaff {
            let parts = key.split(separator: ":", omittingEmptySubsequences: false)
            let tick = Int(parts.first ?? "") ?? 0
            result[tick] = max(result[tick] ?? 0, duration)
        }
        return result
    }

    private static func keyForDuration(tick: Int, staff: Int) -> String { "\(tick):\(staff)" }
    private static func keyForHold(tick: Int, staff: Int?) -> String {
        staff.map { "\(tick):\($0)" } ?? "\(tick):"
    }
}
