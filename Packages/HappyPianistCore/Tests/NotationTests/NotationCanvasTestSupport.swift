import CoreGraphics
@testable import Notation

func makeNotationCanvasFixture(items: [GrandStaffNotationItem] = [], chords: [GrandStaffNotationChord] = [], beams: [GrandStaffNotationBeam] = [], context: GrandStaffNotationContext = .init(), staffSpace: Double = 14) -> GrandStaffNotationSystemCanvasLayoutService.Layout {
    let notation = GrandStaffNotationLayout(items: items, chords: chords, rests: [], ties: [], slurs: [], tuplets: [], barlines: [], beams: beams, ledgerLines: [], marks: [], attributeChanges: [], context: context)
    let header = GrandStaffNotationSignatureLayout.header(context)
    let ink = GrandStaffNotationInkBoundsService().makeLayout(notation: notation.scaledHorizontally(by: 40)).bounds
    let bounds = ink.union(header.bounds).insetBy(dx: 0, dy: -0.2)
    let system = GrandStaffNotationPagePlan.System(id: "canvas-fixture", measures: [], xRange: 0...40, notation: notation, ink: ink, header: header, scale: 1, rect: CGRect(x: 0, y: bounds.minY, width: 40 + header.width - min(0, ink.minX), height: bounds.height))
    return GrandStaffNotationSystemCanvasLayoutService().makeLayout(system: system, staffSpace: staffSpace)
}
