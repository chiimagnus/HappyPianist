import Foundation
import MusicXML
import Practice
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

@MainActor
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
    let commands: [PracticePlaybackCommand]
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
        _ = try controller.handleFingerTips(
            frame.snapshot(keyboardGeometry: keyboardGeometry),
            keyboardGeometry: keyboardGeometry,
            at: .init(seconds: frame.seconds),
            practiceHandMode: .both
        )
        await controller.waitForPendingPlayback()
        observations.append(contentsOf: store.latestKeyContactObservations)
    }

    return SyntheticTraceReplayResult(
        observations: observations,
        commands: sequencer.commands.flatMap(\.self)
    )
}

private func noteOnVelocities(in commands: [PracticePlaybackCommand]) -> [UInt8] {
    commands.compactMap { command in
        guard case let .noteOn(_, velocity) = command.kind else { return nil }
        return velocity
    }
}

private func midiNote(in command: PracticePlaybackCommand) -> Int? {
    switch command.kind {
    case let .noteOn(midi, _), let .noteOff(midi):
        midi
    case .controlChange, .programChange, .pitchBend, .channelPressure, .polyPressure:
        nil
    }
}

private func sourceEventPrefix(for hand: TrackedHandSide) -> String {
    "hand-\(hand.rawValue)-"
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
            startedMIDINotes: [60]
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

    let started = try #require(detector.resultToReturn.first { $0.phase == .started })
    #expect(sequencer.commands == [[
        PracticeLiveNoteEvent(
            contactID: started.id,
            midiNote: 60,
            phase: .noteOn(velocity: 90),
            timestamp: .init(seconds: 1)
        ),
    ].map(\.playbackCommand)])
    #expect(effectHandler.effects.contains(.advanceToNextStep))
}

@Test
@MainActor
func endedContactThatNeverSoundedDoesNotSendNoteOff() async {
    let store = PracticeSessionStateStore()
    let sequencer = FakeSequencerPlaybackService()
    let controller = VirtualPianoInputController(
        detector: FakeKeyContactDetector(resultToReturn: makeTestKeyContactObservations(endedMIDINotes: [60])),
        sequencerPlaybackService: sequencer,
        stateStore: store,
        handGateController: PracticeHandGateController(
            activityGate: HandPianoActivityGate(),
            chordAttemptAccumulator: AlwaysMatchChordAttemptAccumulator(),
            stateStore: store,
            effectHandler: CapturingEffectHandler()
        )
    )

    _ = controller.handleFingerTips(
        .empty,
        keyboardGeometry: makeMinimalKeyboardGeometry(),
        at: .init(seconds: 1),
        practiceHandMode: .both
    )
    await controller.waitForPendingPlayback()

    #expect(sequencer.commands.isEmpty)
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
    #expect(sequencer.commands == [[
        PracticeLiveNoteEvent(
            contactID: left.id,
            midiNote: 60,
            phase: .noteOn(velocity: 90),
            timestamp: .init(seconds: 1)
        ),
    ].map(\.playbackCommand)])

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
    #expect(sequencer.commands.count == 1)

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
    #expect(sequencer.commands.last == [
        PracticeLiveNoteEvent(
            contactID: left.id,
            midiNote: 60,
            phase: .noteOff,
            timestamp: .init(seconds: 3)
        ),
    ].map(\.playbackCommand))
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

    #expect(sequencer.commands.isEmpty)
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

    #expect(sequencer.commands == [[
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
    ].map(\.playbackCommand)])
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
    let lightVelocity = try #require(noteOnVelocities(in: light.commands).first)
    let heavyVelocity = try #require(noteOnVelocities(in: heavy.commands).first)
    #expect(heavyVelocity > lightVelocity)

    let slowPress = try #require(resultByID["slow-press"])
    #expect(noteOnVelocities(in: slowPress.commands).isEmpty)
    #expect(slowPress.commands.isEmpty)
    #expect(slowPress.observations.isEmpty)

    let chord = try #require(resultByID["simultaneous-chord"])
    let chordNoteOns = chord.commands.filter { command in
        if case .noteOn = command.kind { true } else { false }
    }
    #expect(Set(chordNoteOns.compactMap(midiNote)) == [48, 64])
    #expect(Set(noteOnVelocities(in: chordNoteOns)).count == 2)
    #expect(chordNoteOns.first { midiNote(in: $0) == 48 }?.sourceEventID.hasPrefix(sourceEventPrefix(for: .left)) == true)
    #expect(chordNoteOns.first { midiNote(in: $0) == 64 }?.sourceEventID.hasPrefix(sourceEventPrefix(for: .right)) == true)

    let repeated = try #require(resultByID["repeated-note"])
    #expect(repeated.commands.compactMap(midiNote) == [60, 60, 60, 60])
    #expect(repeated.commands.map { command in
        if case .noteOn = command.kind { true } else { false }
    } == [true, false, true, false])
    let repeatedStarts = repeated.commands.filter { command in
        if case .noteOn = command.kind { true } else { false }
    }
    let firstRepeatedStart = try #require(repeatedStarts.first)
    let lastRepeatedStart = try #require(repeatedStarts.last)
    #expect(firstRepeatedStart.sourceEventID != lastRepeatedStart.sourceEventID)

    let trackingLoss = try #require(resultByID["tracking-loss"])
    guard case .noteOff = trackingLoss.commands.last?.kind else {
        Issue.record("Expected tracking loss to release its sounding note")
        return
    }
    #expect(trackingLoss.observations.last?.phase == .ended)
    #expect(trackingLoss.observations.last?.confidence == 0)

    let handCrossing = try #require(resultByID["hand-crossing"])
    #expect(handCrossing.commands.first { midiNote(in: $0) == 72 }?.sourceEventID.hasPrefix(sourceEventPrefix(for: .left)) == true)
    #expect(handCrossing.commands.first { midiNote(in: $0) == 48 }?.sourceEventID.hasPrefix(sourceEventPrefix(for: .right)) == true)

    for id in ["palm-crossing", "unknown-position"] {
        let result = try #require(resultByID[id])
        #expect(result.commands.isEmpty)
        #expect(result.observations.isEmpty)
    }
}
