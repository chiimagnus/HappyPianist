import CoreGraphics
@testable import HappyPianistAVP
import Testing

@Suite
struct GrandStaffChordLayoutServiceTests {
    private let service = GrandStaffChordLayoutService()

    @Test
    func secondsAlternateColumnsFromTheStemDirection() throws {
        let up = try #require(service.makeLayouts(chords: [chord(
            id: "up",
            notes: [note("c", step: 0, stem: .up), note("d", step: 1, stem: .up), note("e", step: 2, stem: .up)]
        )]).first)
        #expect(up.direction == .up)
        #expect(up.noteheadXOffsets == ["c": 0, "d": 1, "e": 0])
        #expect(up.stemStartItemID == "c")
        #expect(up.stemEndItemID == "e")
        #expect(up.stemXOffset == 0.5)

        let down = try #require(service.makeLayouts(chords: [chord(
            id: "down",
            notes: [note("c", step: 0, stem: .down), note("d", step: 1, stem: .down)]
        )]).first)
        #expect(down.direction == .down)
        #expect(down.noteheadXOffsets == ["c": -1, "d": 0])
        #expect(down.stemStartItemID == "d")
        #expect(down.stemEndItemID == "c")
        #expect(down.stemXOffset == -0.5)
    }

    @Test
    func sourceOverrideWinsThenFallbackUsesMiddleLineAndVoicePolicy() throws {
        let layouts = service.makeLayouts(chords: [
            chord(id: "forced", tick: 0, notes: [note("forced", step: 8, stem: .up)]),
            chord(id: "low", tick: 240, notes: [note("low", step: 2)]),
            chord(id: "high", tick: 480, notes: [note("high", step: 6)]),
            chord(id: "voice-1", tick: 720, notes: [note("v1", step: 8, voice: 1)]),
            chord(id: "voice-2", tick: 720, notes: [note("v2", step: 0, voice: 2)]),
        ])
        let byID = Dictionary(uniqueKeysWithValues: layouts.map { ($0.chordID, $0) })

        #expect(byID["forced"]?.direction == .up)
        #expect(byID["low"]?.direction == .up)
        #expect(byID["high"]?.direction == .down)
        #expect(byID["voice-1"]?.direction == .up)
        #expect(byID["voice-2"]?.direction == .down)
    }

    @Test
    func unisonCollisionIsDeterministicAcrossInputOrder() throws {
        let voice1 = chord(id: "voice-1", notes: [note("v1", step: 4, voice: 1)])
        let voice2 = chord(id: "voice-2", notes: [note("v2", step: 4, voice: 2)])
        let forward = service.makeLayouts(chords: [voice1, voice2])
        let reversed = service.makeLayouts(chords: [voice2, voice1])

        #expect(forward == reversed)
        let byID = Dictionary(uniqueKeysWithValues: forward.map { ($0.chordID, $0) })
        #expect(byID["voice-1"]?.noteheadXOffsets["v1"] == 0)
        #expect(byID["voice-2"]?.noteheadXOffsets["v2"] == 1.15)
        #expect(abs((byID["voice-2"]?.stemXOffset ?? 0) - 0.65) < 0.0001)
    }

    @Test
    func crossStaffStemUsesVisualExtremesAndExplicitNoneSuppressesIt() throws {
        let layout = try #require(service.makeLayouts(chords: [chord(
            id: "cross-staff",
            notes: [
                note("upper", staff: 1, step: 0, stem: .up),
                note("lower", staff: 2, step: 8, stem: .up),
            ]
        )]).first)
        #expect(layout.stemStartItemID == "lower")
        #expect(layout.stemEndItemID == "upper")

        let geometry = try #require(service.stemGeometry(
            stem: GrandStaffNotationStem(
                direction: layout.direction,
                isVisible: layout.isStemVisible,
                startItemID: layout.stemStartItemID,
                endItemID: layout.stemEndItemID,
                xOffset: layout.stemXOffset
            ),
            chordX: 50,
            noteheadWidth: 12,
            stemLength: 42,
            noteCentersByID: ["upper": CGPoint(x: 50, y: 80), "lower": CGPoint(x: 50, y: 140)]
        ))
        #expect(geometry.start == CGPoint(x: 56, y: 140))
        #expect(geometry.end == CGPoint(x: 56, y: 38))

        let hidden = try #require(service.makeLayouts(chords: [chord(
            id: "hidden",
            notes: [note("hidden", step: 4, stem: .none)]
        )]).first)
        #expect(hidden.isStemVisible == false)
    }

    private func chord(
        id: String,
        tick: Int = 0,
        notes: [GrandStaffChordLayoutService.Note]
    ) -> GrandStaffChordLayoutService.Chord {
        GrandStaffChordLayoutService.Chord(id: id, tick: tick, notes: notes)
    }

    private func note(
        _ id: String,
        staff: Int = 1,
        step: Int,
        voice: Int = 1,
        stem: MusicXMLStem = .unspecified
    ) -> GrandStaffChordLayoutService.Note {
        GrandStaffChordLayoutService.Note(
            id: id,
            staffNumber: staff,
            staffStep: step,
            voice: voice,
            sourceStem: stem
        )
    }
}
