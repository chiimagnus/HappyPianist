import Foundation

struct GrandStaffGlyphBounds: Equatable, Sendable {
    let minX: Double
    let minY: Double
    let maxX: Double
    let maxY: Double

    var width: Double { maxX - minX }
    var height: Double { maxY - minY }
}

struct GrandStaffEngravingMetrics: Equatable, Sendable {
    // All values are expressed in staff spaces; the viewport applies the display scale once.
    let staffLineThickness = 0.13
    let stemThickness = 0.12
    let beamThickness = 0.50
    let beamSpacing = 0.75
    let ledgerLineThickness = 0.16
    let ledgerLineExtension = 0.40
    let defaultStemLength = 3.50

    func bounds(for token: GrandStaffGlyphToken) -> GrandStaffGlyphBounds? {
        switch token {
        case .noteheadWhole:
            GrandStaffGlyphBounds(minX: -0.69, minY: -0.48, maxX: 0.69, maxY: 0.48)
        case .noteheadHalf, .noteheadBlack:
            GrandStaffGlyphBounds(minX: -0.59, minY: -0.50, maxX: 0.59, maxY: 0.50)
        case .augmentationDot:
            GrandStaffGlyphBounds(minX: -0.13, minY: -0.13, maxX: 0.13, maxY: 0.13)
        default:
            nil
        }
    }
}
