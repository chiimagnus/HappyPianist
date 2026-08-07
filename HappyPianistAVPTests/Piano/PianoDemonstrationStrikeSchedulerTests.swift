@testable import HappyPianistAVP
import Foundation
import Practice
import Testing

@Suite("Piano demonstration strike scheduler")
struct PianoDemonstrationStrikeSchedulerTests {
    @Test func onsetIsContactAndTimeBeforePreRollIsIdle() {
        let scheduler = makeScheduler(now: 10)
        let occurrence = makeOccurrence(onset: 10, release: 10.5, velocity: 90, travelDistance: 0.04)
        let preRoll = scheduler.preRollDuration(
            velocity: occurrence.velocity,
            handTravelDistanceMeters: occurrence.handTravelDistanceMeters
        )

        let beforePreRoll = scheduler.sample(
            occurrence,
            at: occurrence.onset.advanced(by: -preRoll - 0.001)
        )
        let atOnset = scheduler.sample(occurrence)

        #expect(beforePreRoll.phase == .idle)
        #expect(beforePreRoll.contactProgress == 0)
        #expect(atOnset.phase == .hold)
        #expect(atOnset.contactProgress == 1)
    }

    @Test func arbitraryTimeJumpMatchesSequentialSampling() throws {
        let scheduler = makeScheduler(now: 0)
        let occurrence = makeOccurrence(onset: 4, release: 4.5, velocity: 72, travelDistance: 0.03)
        let destination = PerformanceMonotonicInstant(seconds: 3.95)

        let direct = scheduler.sample(occurrence, at: destination)
        let sequential = try #require([
            PerformanceMonotonicInstant(seconds: 3.6),
            PerformanceMonotonicInstant(seconds: 3.8),
            destination,
        ].map { scheduler.sample(occurrence, at: $0) }.last)

        #expect(direct == sequential)
        #expect(direct.phase == .attack)
    }

    @Test func overlappingOccurrencesForOneHandRemainIndependent() throws {
        let scheduler = makeScheduler(now: 10.1)
        let first = makeOccurrence(id: "first", onset: 10, release: 10.4, velocity: 110)
        let second = makeOccurrence(id: "second", onset: 10.2, release: 10.6, velocity: 40)

        let samples = Dictionary(uniqueKeysWithValues: scheduler.samples(for: [first, second]).map {
            ($0.occurrenceID, $0)
        })

        #expect(try #require(samples["first"]).phase == .hold)
        #expect(try #require(samples["second"]).phase == .attack)
        #expect(try #require(samples["first"]).contactProgress == 1)
        #expect(try #require(samples["second"]).contactProgress < 1)
    }

    @Test func attackReboundAndSettledContactPreserveTimelineShape() {
        let scheduler = makeScheduler(now: 0)
        let occurrence = makeOccurrence(onset: 1, release: 1, velocity: 90)
        let preRoll = scheduler.preRollDuration(velocity: 90, handTravelDistanceMeters: 0)

        let prepared = scheduler.sample(occurrence, at: occurrence.onset.advanced(by: -preRoll))
        let lateAttack = scheduler.sample(occurrence, at: occurrence.onset.advanced(by: -0.01))
        let rebound = scheduler.sample(
            occurrence,
            at: occurrence.release.advanced(by: PianoDemonstrationStrikeScheduler.reboundDuration / 2)
        )
        let settling = scheduler.sample(
            occurrence,
            at: occurrence.release.advanced(
                by: PianoDemonstrationStrikeScheduler.reboundDuration +
                    PianoDemonstrationStrikeScheduler.settleDuration / 2
            )
        )
        let complete = scheduler.sample(
            occurrence,
            at: occurrence.release.advanced(
                by: PianoDemonstrationStrikeScheduler.reboundDuration +
                    PianoDemonstrationStrikeScheduler.settleDuration + 0.001
            )
        )

        #expect(prepared.phase == .preparation)
        #expect(prepared.contactProgress == 0)
        #expect(lateAttack.phase == .attack)
        #expect(lateAttack.contactProgress > 0.95)
        #expect(rebound.phase == .release)
        #expect(rebound.contactProgress < 1)
        #expect(rebound.contactProgress >= 0.88)
        #expect(settling.phase == .transition)
        #expect(settling.contactProgress > 0.88)
        #expect(settling.contactProgress < 1)
        #expect(complete.contactProgress == 1)
        #expect(complete.isComplete)
    }

    @Test func velocityAndTravelDistanceControlCappedPreRoll() {
        let scheduler = makeScheduler(now: 0)
        let fast = scheduler.preRollDuration(velocity: 120, handTravelDistanceMeters: 0)
        let slow = scheduler.preRollDuration(velocity: 30, handTravelDistanceMeters: 0)
        let moved = scheduler.preRollDuration(velocity: 30, handTravelDistanceMeters: 0.12)
        let capped = scheduler.preRollDuration(velocity: 30, handTravelDistanceMeters: 100)

        #expect(fast < slow)
        #expect(moved > slow)
        #expect(capped == PianoDemonstrationStrikeScheduler.maximumPreRollDuration)
    }

    private func makeScheduler(now seconds: TimeInterval) -> PianoDemonstrationStrikeScheduler {
        PianoDemonstrationStrikeScheduler(
            performanceClock: PerformanceClock {
                PerformanceMonotonicInstant(seconds: seconds)
            }
        )
    }

    private func makeOccurrence(
        id: String = "occurrence",
        hand: PianoDemonstrationHand = .right,
        onset: TimeInterval,
        release: TimeInterval,
        velocity: UInt8,
        travelDistance: Float = 0
    ) -> PianoDemonstrationStrikeScheduler.Occurrence {
        PianoDemonstrationStrikeScheduler.Occurrence(
            id: id,
            hand: hand,
            onset: PerformanceMonotonicInstant(seconds: onset),
            release: PerformanceMonotonicInstant(seconds: release),
            velocity: velocity,
            handTravelDistanceMeters: travelDistance
        )
    }
}
