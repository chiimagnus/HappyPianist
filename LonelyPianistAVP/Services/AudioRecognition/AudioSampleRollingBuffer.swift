import Foundation

nonisolated struct AudioSampleRollingBuffer: Equatable, Sendable {
    private(set) var capacity: Int
    private var samples: [Float] = []

    init(capacity: Int = 4096) {
        self.capacity = max(1, capacity)
    }

    mutating func setCapacity(_ capacity: Int) {
        self.capacity = max(1, capacity)
        trimToCapacity()
    }

    mutating func append(_ newSamples: [Float]) {
        guard newSamples.isEmpty == false else { return }
        samples.append(contentsOf: newSamples)
        trimToCapacity()
    }

    mutating func reset() {
        samples.removeAll(keepingCapacity: true)
    }

    func window(size: Int) -> [Float]? {
        guard size > 0, samples.count >= size else { return nil }
        return Array(samples.suffix(size))
    }

    var count: Int {
        samples.count
    }

    private mutating func trimToCapacity() {
        if samples.count > capacity {
            samples.removeFirst(samples.count - capacity)
        }
    }
}
