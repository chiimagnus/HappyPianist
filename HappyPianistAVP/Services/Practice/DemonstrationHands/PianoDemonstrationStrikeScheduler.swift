import Foundation
import Practice

enum PianoDemonstrationHandsTiming {
    case transport(PianoDemonstrationTransportTiming)
    case transportPending
    case manual
}

struct PianoDemonstrationTransportTiming: Equatable {
    let generation: Int
    let playbackPositionSeconds: TimeInterval
    let capturedAt: PerformanceMonotonicInstant
    let timeSchedule: AutoplayTimelineTimeSchedule
    let guides: [PianoHighlightGuide]

    func playbackPosition(at instant: PerformanceMonotonicInstant) -> TimeInterval {
        max(0, playbackPositionSeconds + instant.seconds - capturedAt.seconds)
    }

    func performanceInstant(atPlaybackSeconds seconds: TimeInterval) -> PerformanceMonotonicInstant {
        PerformanceMonotonicInstant(
            seconds: capturedAt.seconds - playbackPositionSeconds + seconds
        )
    }
}

struct PianoDemonstrationStrikeScheduler {
    enum Phase: Equatable {
        case idle
        case preparation
        case attack
        case hold
        case release
        case transition
        case complete
    }

    struct Occurrence: Equatable {
        let id: String
        let hand: PianoDemonstrationHand
        let onset: PerformanceMonotonicInstant
        let release: PerformanceMonotonicInstant
        let velocity: UInt8
        let handTravelDistanceMeters: Float

        init(
            id: String,
            hand: PianoDemonstrationHand,
            onset: PerformanceMonotonicInstant,
            release: PerformanceMonotonicInstant,
            velocity: UInt8,
            handTravelDistanceMeters: Float
        ) {
            self.id = id
            self.hand = hand
            self.onset = onset
            self.release = release < onset ? onset : release
            self.velocity = velocity
            self.handTravelDistanceMeters = handTravelDistanceMeters.isFinite
                ? max(0, handTravelDistanceMeters)
                : 0
        }
    }

    struct Sample: Equatable {
        let occurrenceID: String
        let hand: PianoDemonstrationHand
        let phase: Phase
        let phaseProgress: Float
        let contactProgress: Float

        var isComplete: Bool {
            phase == .complete
        }
    }

    static let anticipationDuration: TimeInterval = 0.085
    static let reboundDuration: TimeInterval = 0.065
    static let settleDuration: TimeInterval = 0.105
    static let maximumPreRollDuration: TimeInterval = 0.45

    private static let baseAttackDuration: TimeInterval = 0.155
    private static let velocityAttackReduction: TimeInterval = 0.035
    private static let handTravelSpeedMetersPerSecond: Float = 0.6

    private let performanceClock: PerformanceClock

    init(performanceClock: PerformanceClock) {
        self.performanceClock = performanceClock
    }

    func preRollDuration(
        velocity: UInt8,
        handTravelDistanceMeters: Float
    ) -> TimeInterval {
        let finiteDistance = handTravelDistanceMeters.isFinite
            ? max(0, handTravelDistanceMeters)
            : 0
        let travelDuration = TimeInterval(finiteDistance / Self.handTravelSpeedMetersPerSecond)
        return min(
            Self.maximumPreRollDuration,
            Self.anticipationDuration + attackDuration(velocity: velocity) + travelDuration
        )
    }

    func sample(_ occurrence: Occurrence) -> Sample {
        sample(occurrence, at: performanceClock.now())
    }

    func samples(for occurrences: [Occurrence]) -> [Sample] {
        let instant = performanceClock.now()
        return samples(for: occurrences, at: instant)
    }

    func samples(
        for occurrences: [Occurrence],
        at instant: PerformanceMonotonicInstant
    ) -> [Sample] {
        occurrences.map { sample($0, at: instant) }
    }

    func sample(
        _ occurrence: Occurrence,
        at instant: PerformanceMonotonicInstant
    ) -> Sample {
        let attackDuration = attackDuration(velocity: occurrence.velocity)
        let preparationStart = occurrence.onset.advanced(by: -preRollDuration(
            velocity: occurrence.velocity,
            handTravelDistanceMeters: occurrence.handTravelDistanceMeters
        ))
        let attackStart = occurrence.onset.advanced(by: -attackDuration)
        let releaseEnd = occurrence.release.advanced(by: Self.reboundDuration)
        let transitionEnd = releaseEnd.advanced(by: Self.settleDuration)

        if instant < preparationStart {
            return makeSample(for: occurrence, phase: .idle, phaseProgress: 0, contactProgress: 0)
        }
        if instant < attackStart {
            return makeSample(
                for: occurrence,
                phase: .preparation,
                phaseProgress: normalizedProgress(from: preparationStart, to: attackStart, at: instant),
                contactProgress: 0
            )
        }
        if instant < occurrence.onset {
            let progress = normalizedProgress(from: attackStart, to: occurrence.onset, at: instant)
            return makeSample(
                for: occurrence,
                phase: .attack,
                phaseProgress: progress,
                contactProgress: smoothstep(progress)
            )
        }
        if instant < occurrence.release {
            return makeSample(
                for: occurrence,
                phase: .hold,
                phaseProgress: normalizedProgress(
                    from: occurrence.onset,
                    to: occurrence.release,
                    at: instant
                ),
                contactProgress: 1
            )
        }
        if instant < releaseEnd {
            let progress = normalizedProgress(from: occurrence.release, to: releaseEnd, at: instant)
            return makeSample(
                for: occurrence,
                phase: .release,
                phaseProgress: progress,
                contactProgress: 1 - smoothstep(progress) * 0.12
            )
        }
        if instant < transitionEnd {
            let progress = normalizedProgress(from: releaseEnd, to: transitionEnd, at: instant)
            return makeSample(
                for: occurrence,
                phase: .transition,
                phaseProgress: progress,
                contactProgress: 0.88 + smoothstep(progress) * 0.12
            )
        }
        return makeSample(
            for: occurrence,
            phase: .complete,
            phaseProgress: 1,
            contactProgress: 1
        )
    }

    private func attackDuration(velocity: UInt8) -> TimeInterval {
        let normalizedVelocity = TimeInterval(min(127, Int(velocity))) / 127
        return Self.baseAttackDuration - normalizedVelocity * Self.velocityAttackReduction
    }

    private func normalizedProgress(
        from start: PerformanceMonotonicInstant,
        to end: PerformanceMonotonicInstant,
        at instant: PerformanceMonotonicInstant
    ) -> Float {
        let duration = end.seconds - start.seconds
        guard duration > 0 else { return 1 }
        return Float(min(1, max(0, (instant.seconds - start.seconds) / duration)))
    }

    private func smoothstep(_ value: Float) -> Float {
        let clamped = min(1, max(0, value))
        return clamped * clamped * (3 - 2 * clamped)
    }

    private func makeSample(
        for occurrence: Occurrence,
        phase: Phase,
        phaseProgress: Float,
        contactProgress: Float
    ) -> Sample {
        Sample(
            occurrenceID: occurrence.id,
            hand: occurrence.hand,
            phase: phase,
            phaseProgress: min(1, max(0, phaseProgress)),
            contactProgress: min(1, max(0, contactProgress))
        )
    }
}
