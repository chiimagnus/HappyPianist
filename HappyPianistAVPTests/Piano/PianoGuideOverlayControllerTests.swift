@testable import HappyPianistAVP
import MusicXML
import Practice
import RealityKit
import simd
import Testing

@MainActor
struct PianoGuideOverlayControllerTests {
    @Test func suppressedHighlightsStillAlignTheRestorationParent() throws {
        let keyboardRoot = Entity()
        let controller = PianoGuideOverlayController(keyboardRootEntity: keyboardRoot)
        let frame = try #require(KeyboardFrame(
            a0World: SIMD3<Float>(0, 0.5, 0),
            c8World: SIMD3<Float>(1, 0.5, 0),
            planeHeight: 0.5
        ))

        controller.updateHighlights(
            suppressedMIDINotes: [60],
            highlightGuide: nil,
            keyboardGeometry: PianoKeyboardGeometry(frame: frame, keys: []),
            differentiateWithoutColor: false,
            content: nil
        )

        #expect(abs(keyboardRoot.position.y - 0.5) < 0.0001)
    }

    @Test func onlyCoveredTeacherHandNotesSuppressGuideBeams() throws {
        let keyboardRoot = Entity()
        let controller = PianoGuideOverlayController(keyboardRootEntity: keyboardRoot)
        let geometry = try makeGeometry(notes: [60, 64, 67])
        let guide = PianoHighlightGuide(
            id: 1,
            kind: .trigger,
            tick: 0,
            durationTicks: 1,
            practiceStepIndex: 0,
            activeNotes: [],
            triggeredNotes: [60, 64, 67].map { midiNote in
                PianoHighlightNote(
                    occurrenceID: "note-\(midiNote)",
                    midiNote: midiNote,
                    staff: 1,
                    voice: nil,
                    velocity: 96,
                    onTick: 0,
                    offTick: 1,
                    fingerings: [],
                    handAssignment: ScoreHandAssignment(hand: .right, provenance: .score)
                )
            },
            releasedMIDINotes: []
        )

        controller.updateHighlights(
            suppressedMIDINotes: [60, 64],
            highlightGuide: guide,
            keyboardGeometry: geometry,
            differentiateWithoutColor: false,
            content: nil
        )
        #expect(keyboardRoot.children.count == 1)
        #expect(abs(keyboardRoot.children[0].position.x - 0.048) < 0.0001)

        controller.updateHighlights(
            suppressedMIDINotes: [],
            highlightGuide: guide,
            keyboardGeometry: geometry,
            differentiateWithoutColor: false,
            content: nil
        )
        #expect(keyboardRoot.children.count == 3)
    }

    private func makeGeometry(notes: [Int]) throws -> PianoKeyboardGeometry {
        let frame = try #require(KeyboardFrame(
            a0World: SIMD3<Float>(0, 0.5, 0),
            c8World: SIMD3<Float>(1, 0.5, 0),
            planeHeight: 0.5
        ))
        let keys = notes.enumerated().map { index, midiNote in
            PianoKeyGeometry(
                midiNote: midiNote,
                kind: .white,
                localCenter: SIMD3<Float>(Float(index) * 0.024, -0.015, -0.07),
                localSize: SIMD3<Float>(0.022, 0.03, 0.14),
                surfaceLocalY: 0,
                hitCenterLocal: SIMD3<Float>(Float(index) * 0.024, -0.015, -0.07),
                hitSizeLocal: SIMD3<Float>(0.022, 0.03, 0.14),
                beamFootprintCenterLocal: SIMD3<Float>(Float(index) * 0.024, 0, -0.07),
                beamFootprintSizeLocal: SIMD2<Float>(0.022, 0.14)
            )
        }
        return PianoKeyboardGeometry(frame: frame, keys: keys)
    }
}
