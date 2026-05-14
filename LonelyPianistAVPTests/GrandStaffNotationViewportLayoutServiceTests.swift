@testable import LonelyPianistAVP
import CoreGraphics
import Testing

@Test
func viewportLayoutKeepsExtremeNotesWithinCanvasBounds() {
    let size = CGSize(width: 800, height: 180)

    func makeItem(id: String, staffNumber: Int, staffStep: Int, xPosition: Double) -> GrandStaffNotationItem {
        GrandStaffNotationItem(
            occurrenceID: id,
            staffNumber: staffNumber,
            voice: 1,
            hand: staffNumber >= 2 ? .left : .right,
            midiNote: 60,
            guideID: 1,
            tick: 0,
            xPosition: xPosition,
            staffStep: staffStep,
            showsSharpAccidental: false,
            isHighlighted: false,
            fingeringText: nil,
            noteValue: .quarter,
            chordID: nil,
            noteHeadXOffset: 0,
            stemDirection: .up,
            beamID: nil,
            durationTicks: 480,
            isGrace: false,
            tieStart: false,
            tieStop: false,
            tieEndXPosition: nil,
            articulations: [],
            arpeggiate: nil,
            dotCount: 0
        )
    }

    let items: [GrandStaffNotationItem] = [
        makeItem(id: "treble-hi", staffNumber: 1, staffStep: 26, xPosition: 0.5),
        makeItem(id: "treble-low-gap", staffNumber: 1, staffStep: -12, xPosition: 0.25),
        makeItem(id: "bass-hi-gap", staffNumber: 2, staffStep: 22, xPosition: 0.75),
        makeItem(id: "bass-low", staffNumber: 2, staffStep: -18, xPosition: 0.5),
    ]

    let layout = GrandStaffNotationViewportLayoutService().makeLayout(
        size: size,
        items: items,
        context: GrandStaffNotationContext()
    )

    #expect(layout.lineSpacing >= 8)

    for item in items {
        let y = layout.yPosition(staffStep: item.staffStep, staffNumber: item.staffNumber)
        #expect(y >= layout.noteHeight / 2)
        #expect(y <= layout.requiredHeight - layout.noteHeight / 2)
    }
}

@Test
func viewportLayoutUsesClefLineWhenProvided() {
    let size = CGSize(width: 760, height: 190)

    let context = GrandStaffNotationContext(
        trebleClefSymbol: "𝄞",
        bassClefSymbol: "𝄢",
        trebleClefSignToken: "G",
        trebleClefLine: 2,
        bassClefSignToken: "F",
        bassClefLine: 4
    )

    let layout = GrandStaffNotationViewportLayoutService().makeLayout(
        size: size,
        items: [],
        context: context
    )

    let trebleLine2Y = layout.yPosition(staffStep: 2, staffNumber: 1)
    let bassLine4Y = layout.yPosition(staffStep: 6, staffNumber: 2)
    #expect(abs(layout.trebleClefY - trebleLine2Y) < 0.0001)
    #expect(abs(layout.bassClefY - bassLine4Y) < 0.0001)
}
