import Foundation

struct MusicXMLAttributeTimeline: Equatable {
    private let timeSignatureEvents: [MusicXMLTimeSignatureEvent]
    private let keySignatureEvents: [MusicXMLKeySignatureEvent]
    private let clefEvents: [MusicXMLClefEvent]

    init(
        timeSignatureEvents: [MusicXMLTimeSignatureEvent],
        keySignatureEvents: [MusicXMLKeySignatureEvent],
        clefEvents: [MusicXMLClefEvent]
    ) {
        self.timeSignatureEvents = timeSignatureEvents.sorted { $0.tick < $1.tick }
        self.keySignatureEvents = keySignatureEvents.sorted { $0.tick < $1.tick }
        self.clefEvents = clefEvents.sorted { $0.tick < $1.tick }
    }

    func timeSignature(atTick tick: Int) -> MusicXMLTimeSignatureEvent? {
        lastTimeSignature(atOrBeforeTick: tick, events: timeSignatureEvents)
    }

    func keySignature(atTick tick: Int) -> MusicXMLKeySignatureEvent? {
        lastKeySignature(atOrBeforeTick: tick, events: keySignatureEvents)
    }

    func clef(atTick tick: Int, staffNumber: Int) -> MusicXMLClefEvent? {
        let filtered = clefEvents.filter { event in
            guard let token = event.numberToken, let number = Int(token) else { return staffNumber == 1 }
            return number == staffNumber
        }
        return lastClef(atOrBeforeTick: tick, events: filtered)
    }

    private func lastTimeSignature(atOrBeforeTick tick: Int, events: [MusicXMLTimeSignatureEvent]) -> MusicXMLTimeSignatureEvent? {
        guard events.isEmpty == false else { return nil }

        let clamped = max(0, tick)
        var low = 0
        var high = events.count - 1
        var best = -1

        while low <= high {
            let mid = (low + high) / 2
            if events[mid].tick <= clamped {
                best = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        return best >= 0 ? events[best] : nil
    }

    private func lastKeySignature(atOrBeforeTick tick: Int, events: [MusicXMLKeySignatureEvent]) -> MusicXMLKeySignatureEvent? {
        guard events.isEmpty == false else { return nil }

        let clamped = max(0, tick)
        var low = 0
        var high = events.count - 1
        var best = -1

        while low <= high {
            let mid = (low + high) / 2
            if events[mid].tick <= clamped {
                best = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        return best >= 0 ? events[best] : nil
    }

    private func lastClef(atOrBeforeTick tick: Int, events: [MusicXMLClefEvent]) -> MusicXMLClefEvent? {
        guard events.isEmpty == false else { return nil }

        let clamped = max(0, tick)
        var low = 0
        var high = events.count - 1
        var best = -1

        while low <= high {
            let mid = (low + high) / 2
            if events[mid].tick <= clamped {
                best = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        return best >= 0 ? events[best] : nil
    }
}
