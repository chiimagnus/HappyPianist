import Foundation

struct MusicXMLTempoMap {
    static let ticksPerQuarter = 480

    private struct TempoPoint {
        let tick: Int
        let quarterBPM: Double
        let secondsAtTick: TimeInterval
    }

    private let points: [TempoPoint]

    init(tempoEvents: [MusicXMLTempoEvent], defaultQuarterBPM: Double = 120) {
        let validatedDefault = (defaultQuarterBPM.isFinite && defaultQuarterBPM > 0) ? defaultQuarterBPM : 120

        let validated = tempoEvents
            .filter { $0.quarterBPM.isFinite && $0.quarterBPM > 0 }
            .sorted { lhs, rhs in
                if lhs.tick != rhs.tick { return lhs.tick < rhs.tick }
                return false
            }

        var bpmByTick: [Int: Double] = [:]
        for event in validated {
            bpmByTick[event.tick] = event.quarterBPM
        }

        var dedupedTicks = bpmByTick.keys.sorted()
        if dedupedTicks.isEmpty {
            points = [TempoPoint(tick: 0, quarterBPM: validatedDefault, secondsAtTick: 0)]
            return
        }

        if dedupedTicks[0] != 0 {
            let firstBPM = bpmByTick[dedupedTicks[0]] ?? validatedDefault
            bpmByTick[0] = firstBPM
            dedupedTicks.insert(0, at: 0)
        }

        var built: [TempoPoint] = []
        built.reserveCapacity(dedupedTicks.count)

        var lastTick = 0
        var lastBPM = bpmByTick[0] ?? validatedDefault
        var seconds: TimeInterval = 0

        built.append(TempoPoint(tick: 0, quarterBPM: lastBPM, secondsAtTick: 0))

        for tick in dedupedTicks.dropFirst() {
            let clampedTick = max(0, tick)
            let deltaTicks = max(0, clampedTick - lastTick)
            seconds += Self.seconds(forTicks: deltaTicks, quarterBPM: lastBPM)

            let bpm = bpmByTick[tick] ?? lastBPM
            built.append(TempoPoint(tick: clampedTick, quarterBPM: bpm, secondsAtTick: seconds))

            lastTick = clampedTick
            lastBPM = bpm
        }

        points = built
    }

    func timeSeconds(atTick tick: Int) -> TimeInterval {
        let clampedTick = max(0, tick)
        guard let index = lastPointIndex(atOrBeforeTick: clampedTick) else { return 0 }

        let point = points[index]
        let deltaTicks = max(0, clampedTick - point.tick)
        return point.secondsAtTick + Self.seconds(forTicks: deltaTicks, quarterBPM: point.quarterBPM)
    }

    func durationSeconds(fromTick: Int, toTick: Int) -> TimeInterval {
        let start = max(0, fromTick)
        let end = max(0, toTick)
        guard end > start else { return 0 }
        return max(0, timeSeconds(atTick: end) - timeSeconds(atTick: start))
    }

    private func lastPointIndex(atOrBeforeTick tick: Int) -> Int? {
        guard points.isEmpty == false else { return nil }

        var low = 0
        var high = points.count - 1
        var best = -1

        while low <= high {
            let mid = (low + high) / 2
            if points[mid].tick <= tick {
                best = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        return best >= 0 ? best : nil
    }

    private static func seconds(forTicks ticks: Int, quarterBPM: Double) -> TimeInterval {
        guard ticks > 0 else { return 0 }
        let bpm = max(0.000_1, quarterBPM)
        let quarters = Double(ticks) / Double(ticksPerQuarter)
        let minutes = quarters / bpm
        return minutes * 60
    }
}
