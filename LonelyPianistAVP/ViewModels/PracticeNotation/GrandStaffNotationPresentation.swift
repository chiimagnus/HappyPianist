import CoreGraphics

struct GrandStaffNotationPresentation {
    let notationLayout: GrandStaffNotationLayout
    let viewportLayout: GrandStaffNotationViewportLayoutService.Layout
    let practiceHandMode: PracticeHandMode
    let chordsByID: [String: GrandStaffNotationChord]
    let itemsByChordID: [String: [GrandStaffNotationItem]]
    let beamedChordIDs: Set<String>
    let ledgerStepsByItemID: [String: [Int]]
    let defaultScrollAnchorY: CGFloat
}
