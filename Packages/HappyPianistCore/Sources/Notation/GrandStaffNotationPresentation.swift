import CoreGraphics
import Practice

struct GrandStaffNotationPresentation {
    let notationLayout: GrandStaffNotationLayout
    let viewportLayout: GrandStaffNotationViewportLayoutService.Layout
    let practiceHandMode: PracticeHandMode
    let activeTickRange: Range<Int>?
    let chordsByID: [String: GrandStaffNotationChord]
    let itemsByChordID: [String: [GrandStaffNotationItem]]
    let beamedChordIDs: Set<String>
    let defaultScrollAnchorY: CGFloat
}
