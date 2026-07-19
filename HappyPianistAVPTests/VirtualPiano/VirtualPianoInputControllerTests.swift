import Foundation
@testable import HappyPianistAVP
import simd
import Testing

@MainActor
private final class CapturingEffectHandler: PracticeSessionEffectHandlerProtocol {
    private(set) var effects: [PracticeSessionEffect] = []

    func handle(effect: PracticeSessionEffect) {
        effects.append(effect)
    }
}

private final class AlwaysMatchChordAttemptAccumulator: ChordAttemptAccumulatorProtocol {
    func register(
        pressedNotes _: Set<Int>,
        expectedNotes _: [Int],
        at _: PerformanceMonotonicInstant
    ) -> StepAttemptMatchResult {
        testAttemptOutcome(matched: true)
    }

    func reset() {}
}

@MainActor
private final class FakeKeyContactDetector: KeyContactDetectingProtocol {
    var resultToReturn: [PianoKeyContactObservation]

    init(resultToReturn: [PianoKeyContactObservation]) {
        self.resultToReturn = resultToReturn
    }

    func reset() {}

    func detect(
        fingerTips _: FingerTipsSnapshot,
        keyboardGeometry _: PianoKeyboardGeometry,
        at _: PerformanceMonotonicInstant
    ) -> [PianoKeyContactObservation] {
        resultToReturn
    }
}

@MainActor
private final class FakeSequencerPlaybackService: PracticeSequencerPlaybackServiceProtocol {
    private(set) var commands: [[PracticePlaybackCommand]] = []
    private(set) var liveNoteEvents: [[PracticeLiveNoteEvent]] = []

    func warmUp() throws {}
    func stop(resetCommands _: [PerformanceTransportCommand]) {}
    func load(sequence _: PracticeSequencerSequence) throws {}
    func play(fromSeconds _: TimeInterval) throws {}
    func currentSeconds() -> TimeInterval {
        0
    }

    func playOneShot(commands _: [PracticePlaybackCommand], durationSeconds _: TimeInterval) throws {}
    func execute(commands: [PracticePlaybackCommand]) throws {
        self.commands.append(commands)
    }
    func execute(liveNoteEvents: [PracticeLiveNoteEvent]) throws {
        self.liveNoteEvents.append(liveNoteEvents)
    }

    func stopAllLiveNotes() {}
}

private func makeMinimalKeyboardGeometry() -> PianoKeyboardGeometry {
    let frame = KeyboardFrame(worldFromKeyboard: matrix_identity_float4x4)
    let key = PianoKeyGeometry(
        midiNote: 60,
        kind: .white,
        localCenter: .zero,
        localSize: SIMD3<Float>(1, 0.02, 0.2),
        surfaceLocalY: 0,
        hitCenterLocal: .zero,
        hitSizeLocal: SIMD3<Float>(1, 0.02, 0.2),
        beamFootprintCenterLocal: .zero,
        beamFootprintSizeLocal: SIMD2<Float>(1, 0.2)
    )
    return PianoKeyboardGeometry(frame: frame, keys: [key])
}

private struct SyntheticTraceReplayResult {
    let observations: [PianoKeyContactObservation]
    let events: [PracticeLiveNoteEvent]
}

@MainActor
private func replaySyntheticTrace(
    _ trace: SyntheticHandContactTrace,
    calibration: PianoTouchCalibration,
    keyboardGeometry: PianoKeyboardGeometry
) async throws -> SyntheticTraceReplayResult {
    let store = PracticeSessionStateStore()
    let sequencer = FakeSequencerPlaybackService()
    let controller = VirtualPianoInputController(
        detector: KeyContactDetectionService(calibration: calibration),
        sequencerPlaybackService: sequencer,
        stateStore: store,
        handGateController: PracticeHandGateController(
            activityGate: HandPianoActivityGate(),
            chordAttemptAccumulator: AlwaysMatchChordAttemptAccumulator(),
            stateStore: store,
            effectHandler: CapturingEffectHandler()
        )
    )
    var observations: [PianoKeyContactObservation] = []

    for frame in trace.frames {
        _ = controller.handleFingerTips(
            try frame.snapshot(keyboardGeometry: keyboardGeometry),
            keyboardGeometry: keyboardGeometry,
            at: .init(seconds: frame.seconds),
            practiceHandMode: .both
        )
        await controller.waitForPendingPlayback()
        observations.append(contentsOf: store.latestKeyContactObservations)
    }

    return SyntheticTraceReplayResult(
        observations: observations,
        events: sequencer.liveNoteEvents.flatMap { $0 }
    )
}

private func noteOnVelocities(in events: [PracticeLiveNoteEvent]) -> [UInt8] {
    events.compactMap { event in
        guard case let .noteOn(velocity) = event.phase else { return nil }
        return velocity
    }
}

@Test
@MainActor
func virtualPianoPlaysLiveNotesWhenNotSuppressed() async throws {
    let store = PracticeSessionStateStore()
    store.autoplayState = .off
    store.isManualReplayPlaying = false
    store.steps = [PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1, handAssignment: .unknown)])]
    store.currentStepIndex = 0

    let effectHandler = CapturingEffectHandler()
    let handGateController = PracticeHandGateController(
        activityGate: HandPianoActivityGate(),
        chordAttemptAccumulator: AlwaysMatchChordAttemptAccumulator(),
        stateStore: store,
        effectHandler: effectHandler
    )

    let detector = FakeKeyContactDetector(
        resultToReturn: makeTestKeyContactObservations(
            activeMIDINotes: [60],
            startedMIDINotes: [60],
            endedMIDINotes: [61]
        )
    )
    let sequencer = FakeSequencerPlaybackService()
    let controller = VirtualPianoInputController(
        detector: detector,
        sequencerPlaybackService: sequencer,
        stateStore: store,
        handGateController: handGateController
    )

    _ = controller.handleFingerTips(
        FingerTipsSnapshot.empty,
        keyboardGeometry: makeMinimalKeyboardGeometry(),
        at: .init(seconds: 1),
        practiceHandMode: .both
    )
    await controller.waitForPendingPlayback()

    let ended = try #require(detector.resultToReturn.first { $0.phase == .ended })
    let started = try #require(detector.resultToReturn.first { $0.phase == .started })
    #expect(sequencer.liveNoteEvents == [[
        PracticeLiveNoteEvent(
            contactID: ended.id,
            midiNote: 61,
            phase: .noteOff,
            timestamp: .init(seconds: 1)
        ),
        PracticeLiveNoteEvent(
            contactID: started.id,
            midiNote: 60,
            phase: .noteOn(velocity: 90),
            timestamp: .init(seconds: 1)
        ),
    ]])
    #expect(effectHandler.effects.contains(.advanceToNextStep))
}

@Test
@MainActor
func releasingOneOfTwoContactsOnSameKeyKeepsPhysicalNoteOn() async {
    let store = PracticeSessionStateStore()
    let handGateController = PracticeHandGateController(
        activityGate: HandPianoActivityGate(),
        chordAttemptAccumulator: AlwaysMatchChordAttemptAccumulator(),
        stateStore: store,
        effectHandler: CapturingEffectHandler()
    )
    let calibrationID = UUID()
    let left = makeTestKeyContactObservation(
        midiNote: 60,
        phase: .started,
        hand: .left,
        sequence: 1,
        calibrationID: calibrationID
    )
    let right = makeTestKeyContactObservation(
        midiNote: 60,
        phase: .started,
        hand: .right,
        sequence: 2,
        calibrationID: calibrationID
    )
    let detector = FakeKeyContactDetector(resultToReturn: [left, right])
    let sequencer = FakeSequencerPlaybackService()
    let controller = VirtualPianoInputController(
        detector: detector,
        sequencerPlaybackService: sequencer,
        stateStore: store,
        handGateController: handGateController
    )
    let geometry = makeMinimalKeyboardGeometry()

    _ = controller.handleFingerTips(.empty, keyboardGeometry: geometry, at: .init(seconds: 1), practiceHandMode: .both)
    await controller.waitForPendingPlayback()
    #expect(sequencer.liveNoteEvents == [[
        PracticeLiveNoteEvent(
            contactID: left.id,
            midiNote: 60,
            phase: .noteOn(velocity: 90),
            timestamp: .init(seconds: 1)
        ),
    ]])

    detector.resultToReturn = [
        makeTestKeyContactObservation(
            midiNote: 60,
            phase: .held,
            hand: .left,
            sequence: 1,
            timestamp: .init(seconds: 2),
            calibrationID: calibrationID
        ),
        makeTestKeyContactObservation(
            midiNote: 60,
            phase: .ended,
            hand: .right,
            sequence: 2,
            timestamp: .init(seconds: 2),
            calibrationID: calibrationID
        ),
    ]
    _ = controller.handleFingerTips(.empty, keyboardGeometry: geometry, at: .init(seconds: 2), practiceHandMode: .both)
    await controller.waitForPendingPlayback()
    #expect(sequencer.liveNoteEvents.count == 1)

    detector.resultToReturn = [
        makeTestKeyContactObservation(
            midiNote: 60,
            phase: .ended,
            hand: .left,
            sequence: 1,
            timestamp: .init(seconds: 3),
            calibrationID: calibrationID
        ),
    ]
    _ = controller.handleFingerTips(.empty, keyboardGeometry: geometry, at: .init(seconds: 3), practiceHandMode: .both)
    await controller.waitForPendingPlayback()
    #expect(sequencer.liveNoteEvents.last == [
        PracticeLiveNoteEvent(
            contactID: left.id,
            midiNote: 60,
            phase: .noteOff,
            timestamp: .init(seconds: 3)
        ),
    ])
}

@Test
@MainActor
func virtualPianoDoesNotPlayLiveNotesDuringAutoplay() async {
    let store = PracticeSessionStateStore()
    store.autoplayState = .playing
    store.isManualReplayPlaying = false

    let effectHandler = CapturingEffectHandler()
    let handGateController = PracticeHandGateController(
        activityGate: HandPianoActivityGate(),
        chordAttemptAccumulator: AlwaysMatchChordAttemptAccumulator(),
        stateStore: store,
        effectHandler: effectHandler
    )

    let detector = FakeKeyContactDetector(
        resultToReturn: makeTestKeyContactObservations(
            activeMIDINotes: [60],
            startedMIDINotes: [60],
            endedMIDINotes: [61]
        )
    )
    let sequencer = FakeSequencerPlaybackService()
    let controller = VirtualPianoInputController(
        detector: detector,
        sequencerPlaybackService: sequencer,
        stateStore: store,
        handGateController: handGateController
    )

    _ = controller.handleFingerTips(
        FingerTipsSnapshot.empty,
        keyboardGeometry: makeMinimalKeyboardGeometry(),
        at: .init(seconds: 1),
        practiceHandMode: .both
    )
    await controller.waitForPendingPlayback()

    #expect(sequencer.liveNoteEvents.isEmpty)
}

@Test
@MainActor
func virtualPianoPreservesIndependentChordVelocityAndRejectsSlowPress() async {
    let store = PracticeSessionStateStore()
    let handGateController = PracticeHandGateController(
        activityGate: HandPianoActivityGate(),
        chordAttemptAccumulator: AlwaysMatchChordAttemptAccumulator(),
        stateStore: store,
        effectHandler: CapturingEffectHandler()
    )
    let soft = makeTestKeyContactObservation(
        midiNote: 60,
        phase: .started,
        hand: .left,
        sequence: 1,
        timestamp: .init(seconds: 2),
        resolvedVelocity: 37
    )
    let loud = makeTestKeyContactObservation(
        midiNote: 64,
        phase: .started,
        hand: .right,
        sequence: 2,
        timestamp: .init(seconds: 2.01),
        resolvedVelocity: 111
    )
    let slow = makeTestKeyContactObservation(
        midiNote: 67,
        phase: .started,
        hand: .right,
        finger: .middle,
        sequence: 3,
        timestamp: .init(seconds: 2.02),
        resolvedVelocity: nil
    )
    let sequencer = FakeSequencerPlaybackService()
    let controller = VirtualPianoInputController(
        detector: FakeKeyContactDetector(resultToReturn: [soft, loud, slow]),
        sequencerPlaybackService: sequencer,
        stateStore: store,
        handGateController: handGateController
    )

    _ = controller.handleFingerTips(
        .empty,
        keyboardGeometry: makeMinimalKeyboardGeometry(),
        at: .init(seconds: 2.02),
        practiceHandMode: .both
    )
    await controller.waitForPendingPlayback()

    #expect(sequencer.liveNoteEvents == [[
        PracticeLiveNoteEvent(
            contactID: soft.id,
            midiNote: 60,
            phase: .noteOn(velocity: 37),
            timestamp: .init(seconds: 2)
        ),
        PracticeLiveNoteEvent(
            contactID: loud.id,
            midiNote: 64,
            phase: .noteOn(velocity: 111),
            timestamp: .init(seconds: 2.01)
        ),
    ]])
}

@Test
@MainActor
func syntheticHandContactTracesCoverVelocityLifecycleAndUncertainty() async throws {
    let fixture = try SyntheticHandContactTraceFixtureLoader().load()
    let keyboardGeometry = try #require(
        VirtualPianoKeyGeometryService().generateKeyboardGeometry(
            from: KeyboardFrame(worldFromKeyboard: matrix_identity_float4x4)
        )
    )
    var resultByID: [String: SyntheticTraceReplayResult] = [:]
    for trace in fixture.traces {
        resultByID[trace.id] = try await replaySyntheticTrace(
            trace,
            calibration: fixture.calibration,
            keyboardGeometry: keyboardGeometry
        )
    }

    #expect(Set(resultByID.keys) == [
        "light-touch",
        "heavy-strike",
        "slow-press",
        "simultaneous-chord",
        "repeated-note",
        "palm-crossing",
        "tracking-loss",
        "hand-crossing",
        "unknown-position",
    ])

    let light = try #require(resultByID["light-touch"])
    let heavy = try #require(resultByID["heavy-strike"])
    let lightVelocity = try #require(noteOnVelocities(in: light.events).first)
    let heavyVelocity = try #require(noteOnVelocities(in: heavy.events).first)
    #expect(heavyVelocity > lightVelocity)

    let slowPress = try #require(resultByID["slow-press"])
    #expect(noteOnVelocities(in: slowPress.events).isEmpty)
    #expect(slowPress.observations.contains { $0.phase == .started && $0.resolvedVelocity == nil })

    let chord = try #require(resultByID["simultaneous-chord"])
    let chordNoteOns = chord.events.filter { event in
        if case .noteOn = event.phase { true } else { false }
    }
    #expect(Set(chordNoteOns.map(\.midiNote)) == [48, 64])
    #expect(Set(noteOnVelocities(in: chordNoteOns)).count == 2)
    #expect(chordNoteOns.first { $0.midiNote == 48 }?.contactID.finger.hand == .left)
    #expect(chordNoteOns.first { $0.midiNote == 64 }?.contactID.finger.hand == .right)

    let repeated = try #require(resultByID["repeated-note"])
    #expect(repeated.events.map(\.midiNote) == [60, 60, 60, 60])
    #expect(repeated.events.map { event in
        if case .noteOn = event.phase { true } else { false }
    } == [true, false, true, false])
    let repeatedStarts = repeated.events.filter { event in
        if case .noteOn = event.phase { true } else { false }
    }
    let firstRepeatedStart = try #require(repeatedStarts.first)
    let lastRepeatedStart = try #require(repeatedStarts.last)
    #expect(firstRepeatedStart.contactID != lastRepeatedStart.contactID)

    let trackingLoss = try #require(resultByID["tracking-loss"])
    #expect(trackingLoss.events.last?.phase == .noteOff)
    #expect(trackingLoss.observations.last?.phase == .ended)
    #expect(trackingLoss.observations.last?.confidence == 0)

    let handCrossing = try #require(resultByID["hand-crossing"])
    #expect(handCrossing.events.first { $0.midiNote == 72 }?.contactID.finger.hand == .left)
    #expect(handCrossing.events.first { $0.midiNote == 48 }?.contactID.finger.hand == .right)

    for id in ["palm-crossing", "unknown-position"] {
        let result = try #require(resultByID[id])
        #expect(result.events.isEmpty)
        #expect(result.observations.isEmpty)
    }
}
