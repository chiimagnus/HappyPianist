import Foundation

protocol PracticeTimingClockProtocol: Sendable {
    func nowSeconds() -> TimeInterval
}

struct ContinuousPracticeTimingClock: PracticeTimingClockProtocol {
    private let clock = ContinuousClock()
    private let origin: ContinuousClock.Instant

    init() {
        origin = clock.now
    }

    func nowSeconds() -> TimeInterval {
        let components = origin.duration(to: clock.now).components
        return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
