@testable import HappyPianistAVP
import Diagnostics
import MusicXML
import Practice
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
            keyboardGeometry: geometry,
            reduceMotion: true,
            content: nil
        )
        #expect(abs(rightHand.position.y - contactY - 0.035) < 0.0001)

        controller.update(
            isEnabled: false,
            highlightGuide: nil,
            keyboardGeometry: nil,
            reduceMotion: true,
            content: nil
        )
        #expect(rightHand.isEnabled == false)
    }

    @Test func assetFailureFallsBackToGuideForOnlyTheUnavailableHand() async throws {
        let root = Entity()
        let diagnostics = InMemoryDiagnosticsReporter()
        let loader = SelectiveRigLoader(
            rigs: try await makeRigs(),
            failingHand: .left
        )
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
            keyboardGeometry: geometry,
            reduceMotion: true,
            content: nil
        )
        #expect(initialSuppression.isEmpty)

        for _ in 0 ..< 20 {
            if loader.requestedHands.count == PianoDemonstrationHand.allCases.count { break }
            await Task.yield()
        }
        let suppression = controller.update(
            isEnabled: true,
            highlightGuide: guide,
            keyboardGeometry: geometry,
            reduceMotion: true,
            content: nil
        )
        #expect(suppression == [60])
        #expect(root.findEntity(named: "pianoDemonstrationHand.left") == nil)
        #expect(root.findEntity(named: "pianoDemonstrationHand.right")?.isEnabled == true)

        for _ in 0 ..< 20 {
            if await diagnostics.events.isEmpty == false { break }
            await Task.yield()
        }
        let loadEvents = await diagnostics.events.filter {
            $0.stage == "pianoDemonstrationHands.loadAsset"
        }
        #expect(loadEvents.count == 1)
        #expect(loadEvents.first?.reason.contains("reason=assetUnavailable") == true)
        #expect(loadEvents.first?.reason.contains("/") == false)
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
            keyboardGeometry: geometry,
            reduceMotion: true,
            content: nil
        )
        #expect(releaseSuppression == [60])

        now.withLock { $0 = PerformanceMonotonicInstant(seconds: 1.13) }
        let expiredSuppression = controller.update(
            isEnabled: true,
            highlightGuide: release,
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
private final class SelectiveRigLoader: PianoDemonstrationHandRigLoading {
    enum Failure: Error {
        case injected
        case missingRig
    }

    private let rigs: [PianoDemonstrationHand: PianoDemonstrationHandRig]
    private let failingHand: PianoDemonstrationHand
    private(set) var requestedHands: [PianoDemonstrationHand] = []

    init(
        rigs: [PianoDemonstrationHand: PianoDemonstrationHandRig],
        failingHand: PianoDemonstrationHand
    ) {
        self.rigs = rigs
        self.failingHand = failingHand
    }

    func load(hand: PianoDemonstrationHand) async throws -> PianoDemonstrationHandRig {
        requestedHands.append(hand)
        guard hand != failingHand else { throw Failure.injected }
        guard let rig = rigs[hand] else { throw Failure.missingRig }
        return rig
    }
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
    active: [PianoHighlightNote],
    triggered: [PianoHighlightNote],
    released: Set<Int>
) -> PianoHighlightGuide {
    PianoHighlightGuide(
        id: id,
        kind: kind,
        tick: id,
        durationTicks: 1,
        practiceStepIndex: nil,
        activeNotes: active,
        triggeredNotes: triggered,
        releasedMIDINotes: released
    )
}

private func makeNote(id: String, midiNote: Int, hand: ScoreHand) -> PianoHighlightNote {
    PianoHighlightNote(
        occurrenceID: id,
        midiNote: midiNote,
        staff: hand == .left ? 2 : 1,
        voice: nil,
        velocity: 96,
        onTick: 0,
        offTick: 1,
        fingerings: [],
        handAssignment: ScoreHandAssignment(
            hand: hand,
            provenance: hand == .unknown ? .unresolved : .score
        )
    )
}

private func makeGeometry(notes: [Int] = [60]) -> PianoKeyboardGeometry {
    let frame = KeyboardFrame(
        a0World: SIMD3<Float>(0, 0.5, 0),
        c8World: SIMD3<Float>(1, 0.5, 0),
        planeHeight: 0.5
    )!
    let keys = notes.enumerated().map { index, midiNote in
        let x = 0.12 + Float(index) * 0.024
        return PianoKeyGeometry(
            midiNote: midiNote,
            kind: .white,
            localCenter: SIMD3<Float>(x, -0.015, -0.07),
            localSize: SIMD3<Float>(0.022, 0.03, 0.14),
            surfaceLocalY: 0,
            hitCenterLocal: SIMD3<Float>(x, -0.015, -0.07),
            hitSizeLocal: SIMD3<Float>(0.022, 0.03, 0.14),
            beamFootprintCenterLocal: SIMD3<Float>(x, 0, -0.07),
            beamFootprintSizeLocal: SIMD2<Float>(0.022, 0.14)
        )
    }
    return PianoKeyboardGeometry(frame: frame, keys: keys)
}
