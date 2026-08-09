@testable import HappyPianistAVP
import Diagnostics
import Foundation
import MusicXML
@testable import Practice
import RealityKit
import simd
import Synchronization
import Testing

@MainActor
struct PianoDemonstrationHandsOverlayControllerTests {
    @Test func reusesLoadedHandsAndLiftsReleasedNotesWithoutARKitInput() async throws {
        let root = Entity()
        let controller = try await PianoDemonstrationHandsOverlayController(
            rootEntity: root,
            preloadedRigs: makeRigs()
        )
        let geometry = makeGeometry()
        let triggered = makeGuide(
            id: 1,
            kind: .trigger,
            active: [],
            triggered: [makeNote(id: "right", midiNote: 60, hand: .unknown)],
            released: []
        )

        controller.update(
            isEnabled: true,
            highlightGuide: triggered,
            timing: .manual,
            keyboardGeometry: geometry,
            reduceMotion: true,
            content: nil
        )
        let rightHand = try #require(root.findEntity(named: "pianoDemonstrationHand.right"))
        #expect(root.children.count == 2)
        #expect(rightHand.isEnabled)
        let contactY = rightHand.position.y

        controller.update(
            isEnabled: true,
            highlightGuide: triggered,
            timing: .manual,
            keyboardGeometry: geometry,
            reduceMotion: true,
            content: nil
        )
        #expect(root.children.count == 2)

        controller.update(
            isEnabled: true,
            highlightGuide: makeGuide(
                id: 2,
                kind: .release,
                active: [],
                triggered: [],
                released: [60]
            ),
            timing: .manual,
            keyboardGeometry: geometry,
            reduceMotion: true,
            content: nil
        )
        #expect(abs(rightHand.position.y - contactY - 0.035) < 0.0001)

        controller.update(
            isEnabled: false,
            highlightGuide: nil,
            timing: .manual,
            keyboardGeometry: nil,
            reduceMotion: true,
            content: nil
        )
        #expect(rightHand.isEnabled == false)
    }

    @Test func rightHandTriggerDoesNotResetAnOverlappingLeftStroke() async throws {
        let now = Mutex(PerformanceMonotonicInstant(seconds: 1))
        let root = Entity()
        let controller = try await PianoDemonstrationHandsOverlayController(
            rootEntity: root,
            preloadedRigs: makeRigs(),
            performanceClock: PerformanceClock { now.withLock { $0 } }
        )
        let geometry = makeGeometry(notes: [48, 60])
        let leftNote = makeNote(id: "left", midiNote: 48, hand: .left, velocity: 96)
        let leftGuide = makeGuide(
            id: 1,
            kind: .trigger,
            active: [],
            triggered: [leftNote],
            released: []
        )

        controller.update(
            isEnabled: true,
            highlightGuide: leftGuide,
            timing: .manual,
            keyboardGeometry: geometry,
            reduceMotion: false,
            content: nil
        )
        now.withLock { $0 = PerformanceMonotonicInstant(seconds: 1.16) }
        controller.update(
            isEnabled: true,
            highlightGuide: leftGuide,
            timing: .manual,
            keyboardGeometry: geometry,
            reduceMotion: false,
            content: nil
        )
        let leftHand = try #require(root.findEntity(named: "pianoDemonstrationHand.left"))
        let leftPositionBeforeRightTrigger = leftHand.position

        controller.update(
            isEnabled: true,
            highlightGuide: makeGuide(
                id: 2,
                kind: .trigger,
                active: [],
                triggered: [
                    leftNote,
                    makeNote(id: "right", midiNote: 60, hand: .right, velocity: 96),
                ],
                released: []
            ),
            timing: .manual,
            keyboardGeometry: geometry,
            reduceMotion: false,
            content: nil
        )

        #expect(simd_distance(leftHand.position, leftPositionBeforeRightTrigger) < 0.001)
        controller.reset()
    }

    @Test func handsUseTheirOwnStrikeVelocity() async throws {
        let now = Mutex(PerformanceMonotonicInstant(seconds: 1))
        let root = Entity()
        let controller = try await PianoDemonstrationHandsOverlayController(
            rootEntity: root,
            preloadedRigs: makeRigs(),
            performanceClock: PerformanceClock { now.withLock { $0 } }
        )
        let guide = makeGuide(
            id: 1,
            kind: .trigger,
            active: [],
            triggered: [
                makeNote(id: "left", midiNote: 48, hand: .left, velocity: 120),
                makeNote(id: "right", midiNote: 60, hand: .right, velocity: 30),
            ],
            released: []
        )
        let geometry = makeGeometry(notes: [48, 60])

        controller.update(
            isEnabled: true,
            highlightGuide: guide,
            timing: .manual,
            keyboardGeometry: geometry,
            reduceMotion: false,
            content: nil
        )
        now.withLock { $0 = PerformanceMonotonicInstant(seconds: 1.16) }
        controller.update(
            isEnabled: true,
            highlightGuide: guide,
            timing: .manual,
            keyboardGeometry: geometry,
            reduceMotion: false,
            content: nil
        )

        let leftHand = try #require(root.findEntity(named: "pianoDemonstrationHand.left"))
        let rightHand = try #require(root.findEntity(named: "pianoDemonstrationHand.right"))
        #expect(leftHand.position.y + 0.0005 < rightHand.position.y)
        controller.reset()
    }

    @Test func transportSamplingContactsAtThePlannedOnset() async throws {
        let now = Mutex(PerformanceMonotonicInstant(seconds: 100))
        let root = Entity()
        let controller = try await PianoDemonstrationHandsOverlayController(
            rootEntity: root,
            preloadedRigs: makeRigs(),
            performanceClock: PerformanceClock { now.withLock { $0 } }
        )
        let guide = makeGuide(
            id: 10,
            kind: .trigger,
            tick: 1_920,
            active: [],
            triggered: [makeNote(
                id: "timed-right",
                midiNote: 60,
                hand: .right,
                onTick: 1_920,
                offTick: 3_840
            )],
            released: []
        )
        let timing = makeTransportTiming(
            guide: guide,
            playbackPositionSeconds: 0.1,
            capturedAtSeconds: 100
        )
        let geometry = makeGeometry()

        controller.update(
            isEnabled: true,
            highlightGuide: nil,
            timing: .transport(timing),
            keyboardGeometry: geometry,
            reduceMotion: false,
            content: nil
        )
        let rightHand = try #require(root.findEntity(named: "pianoDemonstrationHand.right"))
        let preparedY = rightHand.position.y

        now.withLock { $0 = PerformanceMonotonicInstant(seconds: 100.2) }
        controller.update(
            isEnabled: true,
            highlightGuide: nil,
            timing: .transport(timing),
            keyboardGeometry: geometry,
            reduceMotion: false,
            content: nil
        )

        #expect(preparedY > rightHand.position.y + 0.005)
        controller.reset()
    }

    @Test func transportPreparesAtMaximumTravelLookaheadInsteadOfAudioHorizon() async throws {
        let now = Mutex(PerformanceMonotonicInstant(seconds: 100))
        let root = Entity()
        let controller = try await PianoDemonstrationHandsOverlayController(
            rootEntity: root,
            preloadedRigs: makeRigs(),
            performanceClock: PerformanceClock { now.withLock { $0 } }
        )
        let current = makeGuide(
            id: 1,
            kind: .trigger,
            active: [],
            triggered: [makeNote(id: "current", midiNote: 60, hand: .right)],
            released: []
        )
        let upcoming = makeGuide(
            id: 2,
            kind: .trigger,
            tick: 480,
            active: [],
            triggered: [makeNote(
                id: "upcoming",
                midiNote: 72,
                hand: .right,
                onTick: 480,
                offTick: 960
            )],
            released: []
        )
        let geometry = makeGeometry(keyCenters: [60: 0.12, 72: 0.60])

        controller.update(
            isEnabled: true,
            highlightGuide: current,
            timing: .manual,
            keyboardGeometry: geometry,
            reduceMotion: true,
            content: nil
        )
        let timing = makeTransportTiming(
            guides: [current, upcoming],
            playbackPositionSeconds: 0,
            capturedAtSeconds: 100
        )
        now.withLock { $0 = PerformanceMonotonicInstant(seconds: 100.11) }

        let suppression = controller.update(
            isEnabled: true,
            highlightGuide: nil,
            timing: .transport(timing),
            keyboardGeometry: geometry,
            reduceMotion: false,
            content: nil
        )

        #expect(suppression == [72])
        #expect(root.findEntity(named: "pianoDemonstrationHand.right")?.isEnabled == true)
        controller.reset()
    }

    @Test func sameHandOccurrencesKeepTheirOwnTransportProgress() async throws {
        let now = Mutex(PerformanceMonotonicInstant(seconds: 100))
        let root = Entity()
        let controller = try await PianoDemonstrationHandsOverlayController(
            rootEntity: root,
            preloadedRigs: makeRigs(),
            performanceClock: PerformanceClock { now.withLock { $0 } }
        )
        let guide = makeGuide(
            id: 1,
            kind: .trigger,
            active: [],
            triggered: [
                makeNote(id: "first", midiNote: 60, hand: .right, onTick: 0, offTick: 120),
                makeNote(id: "second", midiNote: 64, hand: .right, onTick: 480, offTick: 960),
            ],
            released: []
        )
        let timing = makeTransportTiming(
            guide: guide,
            playbackPositionSeconds: 0,
            capturedAtSeconds: 100
        )
        let secondOnset = try #require(
            timing.contactTimeline.contact(forOccurrenceID: "second")?.onsetSeconds
        )
        now.withLock {
            $0 = PerformanceMonotonicInstant(seconds: 100 + secondOnset - 0.05)
        }

        controller.update(
            isEnabled: true,
            highlightGuide: guide,
            timing: .transport(timing),
            keyboardGeometry: makeGeometry(notes: [60, 64]),
            reduceMotion: false,
            content: nil
        )

        let rightHand = try #require(root.findEntity(named: "pianoDemonstrationHand.right"))
        #expect(rightHand.position.y > 0.046)
        controller.reset()
    }

    @Test func unreachableTargetFallsBackToItsKeyWhileReachableTargetsStayOnTheRig() async throws {
        let controller = try await PianoDemonstrationHandsOverlayController(preloadedRigs: makeRigs())
        let guide = makeGuide(
            id: 1,
            kind: .trigger,
            active: [],
            triggered: [60, 61, 62, 63, 64].map { midiNote in
                makeNote(id: "target-\(midiNote)", midiNote: midiNote, hand: .right)
            },
            released: []
        )

        let suppression = controller.update(
            isEnabled: true,
            highlightGuide: guide,
            timing: .manual,
            keyboardGeometry: makeGeometry(
                notes: [60, 61, 62, 63, 64],
                keyDepths: [64: -0.40]
            ),
            reduceMotion: true,
            content: nil
        )

        #expect(suppression == Set([60, 61, 62, 63]))
        controller.reset()
    }

    @Test func manualTimingFallbackIsReportedOncePerGuide() async throws {
        let now = Mutex(PerformanceMonotonicInstant(seconds: 1))
        let diagnostics = InMemoryDiagnosticsReporter()
        let guide = makeGuide(
            id: 42,
            kind: .trigger,
            active: [],
            triggered: [makeNote(id: "manual", midiNote: 60, hand: .right)],
            released: []
        )
        let controller = try await PianoDemonstrationHandsOverlayController(
            diagnosticsReporter: diagnostics,
            preloadedRigs: makeRigs(),
            performanceClock: PerformanceClock { now.withLock { $0 } }
        )

        for _ in 0 ..< 2 {
            controller.update(
                isEnabled: true,
                highlightGuide: guide,
                timing: .manual,
                keyboardGeometry: makeGeometry(),
                reduceMotion: false,
                content: nil
            )
        }

        let events = await diagnostics.events.filter {
            $0.stage == "pianoDemonstrationHands.timing"
        }
        #expect(events.count == 1)
        #expect(events.first?.reason == "mode=manual;reason=transportUnavailable")
        controller.reset()
    }

    @Test func assetFailureFallsBackToGuideForOnlyTheUnavailableHand() async throws {
        let root = Entity()
        let diagnostics = InMemoryDiagnosticsReporter()
        let loader = ControllableRigLoader(rigs: try await makeRigs())
        let controller = PianoDemonstrationHandsOverlayController(
            rootEntity: root,
            diagnosticsReporter: diagnostics,
            rigLoader: loader
        )
        let geometry = makeGeometry(notes: [48, 60])
        let guide = makeGuide(
            id: 1,
            kind: .trigger,
            active: [],
            triggered: [
                makeNote(id: "left", midiNote: 48, hand: .left),
                makeNote(id: "right", midiNote: 60, hand: .right),
            ],
            released: []
        )

        let rawCoverage = PianoDemonstrationHandTargetResolver().resolve(
            highlightGuide: guide,
            keyboardGeometry: geometry
        )
        let availableCoverage = rawCoverage.limitedToAvailableHands([.right])
        #expect(availableCoverage.coveredTargets(for: .left).isEmpty)
        #expect(availableCoverage.coveredTargets(for: .right).map(\.midiNote) == [60])
        #expect(availableCoverage.uncoveredKeys.first { $0.occurrenceID == "left" }?.reason == .assetUnavailable)

        let initialSuppression = controller.update(
            isEnabled: true,
            highlightGuide: guide,
            timing: .manual,
            keyboardGeometry: geometry,
            reduceMotion: true,
            content: nil
        )
        #expect(initialSuppression.isEmpty)

        await loader.waitForRequest(for: .left)
        loader.resume(hand: .left, with: .failure(ControllableRigLoader.Failure.injected))
        await loader.waitForRequest(for: .right)
        let rightRig = try #require(loader.rig(for: .right))
        loader.resume(hand: .right, with: .success(rightRig))
        await processPendingMainActorWork()

        let suppression = controller.update(
            isEnabled: true,
            highlightGuide: guide,
            timing: .manual,
            keyboardGeometry: geometry,
            reduceMotion: true,
            content: nil
        )
        #expect(suppression == [60])
        #expect(root.findEntity(named: "pianoDemonstrationHand.left") == nil)
        #expect(root.findEntity(named: "pianoDemonstrationHand.right")?.isEnabled == true)

        let loadEvents = await diagnostics.events.filter {
            $0.stage == "pianoDemonstrationHands.loadAsset"
        }
        #expect(loadEvents.count == 1)
        #expect(loadEvents.first?.reason.contains("reason=assetUnavailable") == true)
        #expect(loadEvents.first?.reason.contains("/") == false)
    }

    @Test func resetRejectsALateAssetLoadWithoutRestoringHandsOrSuppression() async throws {
        let root = Entity()
        let loader = ControllableRigLoader(rigs: try await makeRigs())
        let controller = PianoDemonstrationHandsOverlayController(rootEntity: root, rigLoader: loader)
        let guide = makeGuide(
            id: 1,
            kind: .trigger,
            active: [],
            triggered: [makeNote(id: "late", midiNote: 60, hand: .right)],
            released: []
        )

        await loader.waitForRequest(for: .left)
        #expect(controller.update(
            isEnabled: true,
            highlightGuide: guide,
            timing: .manual,
            keyboardGeometry: makeGeometry(),
            reduceMotion: true,
            content: nil
        ).isEmpty)

        controller.reset()
        let leftRig = try #require(loader.rig(for: .left))
        loader.resume(hand: .left, with: .success(leftRig))
        await processPendingMainActorWork()

        #expect(root.children.isEmpty)
        #expect(controller.requiresReplacement)
        #expect(controller.update(
            isEnabled: true,
            highlightGuide: guide,
            timing: .manual,
            keyboardGeometry: makeGeometry(),
            reduceMotion: true,
            content: nil
        ).isEmpty)
    }

    @Test func repeatedMIDINoteOccurrencesAndReduceMotionLeaveNoAnimatingState() async throws {
        let now = Mutex(PerformanceMonotonicInstant(seconds: 1))
        let root = Entity()
        let controller = try await PianoDemonstrationHandsOverlayController(
            rootEntity: root,
            preloadedRigs: makeRigs(),
            performanceClock: PerformanceClock { now.withLock { $0 } }
        )
        let guide = makeGuide(
            id: 1,
            kind: .trigger,
            active: [],
            triggered: [
                makeNote(id: "first-60", midiNote: 60, hand: .right),
                makeNote(id: "second-60", midiNote: 60, hand: .right),
            ],
            released: []
        )

        let initialSuppression = controller.update(
            isEnabled: true,
            highlightGuide: guide,
            timing: .manual,
            keyboardGeometry: makeGeometry(),
            reduceMotion: true,
            content: nil
        )
        let rightHand = try #require(root.findEntity(named: "pianoDemonstrationHand.right"))
        let staticPosition = rightHand.position
        now.withLock { $0 = PerformanceMonotonicInstant(seconds: 2) }

        let laterSuppression = controller.update(
            isEnabled: true,
            highlightGuide: guide,
            timing: .manual,
            keyboardGeometry: makeGeometry(),
            reduceMotion: true,
            content: nil
        )

        #expect(initialSuppression == [60])
        #expect(laterSuppression == [60])
        #expect(simd_distance(rightHand.position, staticPosition) < 0.0001)
        controller.reset()
    }

    @Test func suppressionResidencePreventsSingleFrameGuideFlicker() async throws {
        let now = Mutex(PerformanceMonotonicInstant(seconds: 1))
        let controller = try await PianoDemonstrationHandsOverlayController(
            preloadedRigs: makeRigs(),
            performanceClock: PerformanceClock {
                now.withLock { $0 }
            },
            suppressionMinimumResidence: 0.12
        )
        let geometry = makeGeometry()
        let triggered = makeGuide(
            id: 1,
            kind: .trigger,
            active: [],
            triggered: [makeNote(id: "right", midiNote: 60, hand: .right)],
            released: []
        )

        let triggeredSuppression = controller.update(
            isEnabled: true,
            highlightGuide: triggered,
            timing: .manual,
            keyboardGeometry: geometry,
            reduceMotion: true,
            content: nil
        )
        #expect(triggeredSuppression == [60])

        let release = makeGuide(
            id: 2,
            kind: .release,
            active: [],
            triggered: [],
            released: [60]
        )
        let releaseSuppression = controller.update(
            isEnabled: true,
            highlightGuide: release,
            timing: .manual,
            keyboardGeometry: geometry,
            reduceMotion: true,
            content: nil
        )
        #expect(releaseSuppression == [60])

        now.withLock { $0 = PerformanceMonotonicInstant(seconds: 1.13) }
        let expiredSuppression = controller.update(
            isEnabled: true,
            highlightGuide: release,
            timing: .manual,
            keyboardGeometry: geometry,
            reduceMotion: true,
            content: nil
        )
        #expect(expiredSuppression.isEmpty)
    }

    @Test func resetRemovesRetainedHandEntities() async throws {
        let root = Entity()
        root.addChild(Entity())
        let controller = try await PianoDemonstrationHandsOverlayController(
            rootEntity: root,
            preloadedRigs: makeRigs()
        )

        #expect(root.children.count == 3)

        controller.reset()

        #expect(root.children.isEmpty)
        #expect(root.parent == nil)
        #expect(controller.requiresReplacement)
    }
}

@MainActor
private final class ControllableRigLoader: PianoDemonstrationHandRigLoading {
    enum Failure: Error {
        case injected
    }

    private let rigs: [PianoDemonstrationHand: PianoDemonstrationHandRig]
    private var continuationByHand: [
        PianoDemonstrationHand: CheckedContinuation<Result<PianoDemonstrationHandRig, Error>, Never>
    ] = [:]
    private var requestWaiterByHand: [PianoDemonstrationHand: CheckedContinuation<Void, Never>] = [:]
    private var requestedHands = Set<PianoDemonstrationHand>()

    init(rigs: [PianoDemonstrationHand: PianoDemonstrationHandRig]) {
        self.rigs = rigs
    }

    func load(hand: PianoDemonstrationHand) async throws -> PianoDemonstrationHandRig {
        let result: Result<PianoDemonstrationHandRig, Error> = await withCheckedContinuation { continuation in
            continuationByHand[hand] = continuation
            requestedHands.insert(hand)
            requestWaiterByHand.removeValue(forKey: hand)?.resume()
        }
        return try result.get()
    }

    func waitForRequest(for hand: PianoDemonstrationHand) async {
        guard requestedHands.contains(hand) == false else { return }
        await withCheckedContinuation { continuation in
            requestWaiterByHand[hand] = continuation
        }
    }

    func rig(for hand: PianoDemonstrationHand) -> PianoDemonstrationHandRig? {
        rigs[hand]
    }

    func resume(
        hand: PianoDemonstrationHand,
        with result: Result<PianoDemonstrationHandRig, Error>
    ) {
        precondition(continuationByHand[hand] != nil, "load was not waiting for \(hand)")
        continuationByHand.removeValue(forKey: hand)?.resume(returning: result)
    }
}

@MainActor
private func processPendingMainActorWork() async {
    await Task { @MainActor in }.value
}

@MainActor
private func makeRigs() async throws -> [PianoDemonstrationHand: PianoDemonstrationHandRig] {
    var rigs: [PianoDemonstrationHand: PianoDemonstrationHandRig] = [:]
    for hand in PianoDemonstrationHand.allCases {
        rigs[hand] = try await PianoDemonstrationHandRig.load(hand: hand)
    }
    return rigs
}

private func makeGuide(
    id: Int,
    kind: PianoHighlightGuideKind,
    tick: Int? = nil,
    active: [PianoHighlightNote],
    triggered: [PianoHighlightNote],
    released: Set<Int>
) -> PianoHighlightGuide {
    PianoHighlightGuide(
        id: id,
        kind: kind,
        tick: tick ?? id,
        durationTicks: 1,
        practiceStepIndex: nil,
        activeNotes: active,
        triggeredNotes: triggered,
        releasedMIDINotes: released
    )
}

private func makeNote(
    id: String,
    midiNote: Int,
    hand: ScoreHand,
    velocity: UInt8 = 96,
    onTick: Int = 0,
    offTick: Int = 1
) -> PianoHighlightNote {
    PianoHighlightNote(
        occurrenceID: id,
        midiNote: midiNote,
        staff: hand == .left ? 2 : 1,
        voice: nil,
        velocity: velocity,
        onTick: onTick,
        offTick: offTick,
        fingerings: [],
        handAssignment: ScoreHandAssignment(
            hand: hand,
            provenance: hand == .unknown ? .unresolved : .score
        )
    )
}

private func makeTransportTiming(
    guide: PianoHighlightGuide,
    playbackPositionSeconds: TimeInterval,
    capturedAtSeconds: TimeInterval
) -> PianoDemonstrationTransportTiming {
    makeTransportTiming(
        guides: [guide],
        playbackPositionSeconds: playbackPositionSeconds,
        capturedAtSeconds: capturedAtSeconds
    )
}

private func makeTransportTiming(
    guides: [PianoHighlightGuide],
    playbackPositionSeconds: TimeInterval,
    capturedAtSeconds: TimeInterval
) -> PianoDemonstrationTransportTiming {
    let tempoMap = MusicXMLTempoMap(tempoEvents: [])
    var events = guides.flatMap(\.triggeredNotes).enumerated().flatMap { index, note in
        [
            AutoplayPerformanceTimeline.Event(
                id: index * 2,
                sourceEventID: note.occurrenceID,
                tick: note.onTick,
                kind: .noteOn(midi: note.midiNote, velocity: note.velocity)
            ),
            AutoplayPerformanceTimeline.Event(
                id: index * 2 + 1,
                sourceEventID: note.occurrenceID,
                tick: note.offTick,
                kind: .noteOff(midi: note.midiNote)
            ),
        ]
    }
    for (index, guide) in guides.enumerated() {
        events.append(AutoplayPerformanceTimeline.Event(
            id: events.count,
            tick: guide.tick,
            kind: .advanceGuide(index: index, guideID: guide.id)
        ))
    }
    events.sort {
        if $0.tick != $1.tick { return $0.tick < $1.tick }
        return $0.id < $1.id
    }
    let timeline = AutoplayPerformanceTimeline(events: events)
    let schedule = AutoplayTimelineTimeSchedule(
        timeline: timeline,
        tickToSeconds: { tempoMap.timeSeconds(atTick: $0) },
        startTick: 0,
        leadInSeconds: 0.05
    )
    let contactTimeline = PianoKeyContactTimeline(contacts: guides.flatMap { guide in
        guide.triggeredNotes.map { note in
            let noteOnEvent = events.first {
                guard $0.sourceEventID == note.occurrenceID else { return false }
                if case .noteOn = $0.kind { return true }
                return false
            }
            let noteOffEvent = events.first {
                guard $0.sourceEventID == note.occurrenceID else { return false }
                if case .noteOff = $0.kind { return true }
                return false
            }
            let timing: PianoKeyContactTimeline.Timing
            if let noteOnEvent,
               let noteOffEvent,
               let onsetSeconds = schedule.timeSeconds(forEventID: noteOnEvent.id),
               let releaseSeconds = schedule.timeSeconds(forEventID: noteOffEvent.id)
            {
                timing = .scheduled(onsetSeconds: onsetSeconds, releaseSeconds: releaseSeconds)
            } else {
                timing = .unplannable(.missingNoteOff)
            }
            return PianoKeyContactTimeline.Contact(
                occurrenceID: note.occurrenceID,
                midiNote: note.midiNote,
                staff: note.staff ?? 0,
                handAssignment: note.handAssignment,
                fingerings: note.fingerings,
                velocity: note.velocity,
                guideID: guide.id,
                stepIndex: guide.practiceStepIndex,
                carriedIn: false,
                timing: timing
            )
        }
    })
    return PianoDemonstrationTransportTiming(
        generation: 1,
        playbackPositionSeconds: playbackPositionSeconds,
        capturedAt: PerformanceMonotonicInstant(seconds: capturedAtSeconds),
        timeSchedule: schedule,
        contactTimeline: contactTimeline,
        guides: guides
    )
}

private func makeGeometry(
    notes: [Int] = [60],
    keyDepths: [Int: Float] = [:]
) -> PianoKeyboardGeometry {
    makeGeometry(keyCenters: Dictionary(uniqueKeysWithValues: notes.enumerated().map { index, midiNote in
        (midiNote, 0.12 + Float(index) * 0.024)
    }), keyDepths: keyDepths)
}

private func makeGeometry(
    keyCenters: [Int: Float],
    keyDepths: [Int: Float] = [:]
) -> PianoKeyboardGeometry {
    let frame = KeyboardFrame(
        a0World: SIMD3<Float>(0, 0.5, 0),
        c8World: SIMD3<Float>(1, 0.5, 0),
        planeHeight: 0.5
    )!
    let keys = keyCenters.keys.sorted().compactMap { midiNote -> PianoKeyGeometry? in
        guard let x = keyCenters[midiNote] else { return nil }
        let z = keyDepths[midiNote] ?? -0.07
        return PianoKeyGeometry(
            midiNote: midiNote,
            kind: .white,
            localCenter: SIMD3<Float>(x, -0.015, z),
            localSize: SIMD3<Float>(0.022, 0.03, 0.14),
            surfaceLocalY: 0,
            hitCenterLocal: SIMD3<Float>(x, -0.015, z),
            hitSizeLocal: SIMD3<Float>(0.022, 0.03, 0.14),
            beamFootprintCenterLocal: SIMD3<Float>(x, 0, z),
            beamFootprintSizeLocal: SIMD2<Float>(0.022, 0.14)
        )
    }
    return PianoKeyboardGeometry(frame: frame, keys: keys)
}
