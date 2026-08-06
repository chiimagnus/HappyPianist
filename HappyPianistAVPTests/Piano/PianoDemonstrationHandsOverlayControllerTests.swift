@testable import HappyPianistAVP
import MusicXML
import Practice
import RealityKit
import simd
import Testing

@MainActor
struct PianoDemonstrationHandsOverlayControllerTests {
    @Test func reusesFixedHandsAndLiftsReleasedNotesWithoutARKitInput() throws {
        let root = Entity()
        let controller = PianoDemonstrationHandsOverlayController(rootEntity: root)
        let geometry = makeGeometry()
        let triggered = makeGuide(
            id: 1,
            kind: .trigger,
            active: [],
            triggered: [makeNote(id: "right", midiNote: 60, hand: .right)],
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
        #expect(abs(rightHand.position.y) < 0.0001)

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
        #expect(abs(rightHand.position.y - 0.035) < 0.0001)

        controller.update(
            isEnabled: false,
            highlightGuide: nil,
            keyboardGeometry: nil,
            reduceMotion: true,
            content: nil
        )
        #expect(rightHand.isEnabled == false)
    }

    @Test func resetRemovesRetainedHandEntities() {
        let root = Entity()
        root.addChild(Entity())
        let controller = PianoDemonstrationHandsOverlayController(rootEntity: root)

        #expect(root.children.count == 3)

        controller.reset()

        #expect(root.children.isEmpty)
        #expect(root.parent == nil)
        #expect(controller.requiresReplacement)
    }
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
        handAssignment: ScoreHandAssignment(hand: hand, provenance: .score)
    )
}

private func makeGeometry() -> PianoKeyboardGeometry {
    let frame = KeyboardFrame(
        a0World: SIMD3<Float>(0, 0.5, 0),
        c8World: SIMD3<Float>(1, 0.5, 0),
        planeHeight: 0.5
    )!
    let key = PianoKeyGeometry(
        midiNote: 60,
        kind: .white,
        localCenter: SIMD3<Float>(0.12, -0.015, -0.07),
        localSize: SIMD3<Float>(0.022, 0.03, 0.14),
        surfaceLocalY: 0,
        hitCenterLocal: SIMD3<Float>(0.12, -0.015, -0.07),
        hitSizeLocal: SIMD3<Float>(0.022, 0.03, 0.14),
        beamFootprintCenterLocal: SIMD3<Float>(0.12, 0, -0.07),
        beamFootprintSizeLocal: SIMD2<Float>(0.022, 0.14)
    )
    return PianoKeyboardGeometry(frame: frame, keys: [key])
}
