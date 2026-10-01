import Notation
import simd

struct SpatialBookDisplayMetrics: Equatable {
    static let standard = Self()

    let folioHeightMeters: Float
    let spreadHeightMeters: Float
    let minimumReadableHeightMeters: Float
    let folioSpacingMeters: Float
    let depthStepMeters: Float

    init(
        folioHeightMeters: Float = 0.30,
        spreadHeightMeters: Float = 0.42,
        minimumReadableHeightMeters: Float = 0.24,
        folioSpacingMeters: Float = 0.16,
        depthStepMeters: Float = 0.055
    ) {
        self.folioHeightMeters = folioHeightMeters
        self.spreadHeightMeters = spreadHeightMeters
        self.minimumReadableHeightMeters = minimumReadableHeightMeters
        self.folioSpacingMeters = folioSpacingMeters
        self.depthStepMeters = depthStepMeters
    }

    var folioWidthMeters: Float {
        effectiveFolioHeightMeters / 1.4
    }

    var effectiveFolioHeightMeters: Float {
        max(folioHeightMeters, minimumReadableHeightMeters)
    }

    var spreadWidthMeters: Float {
        effectiveSpreadHeightMeters * Float(
            GrandStaffNotationPageGeometry.canonical.spreadWidth
                / GrandStaffNotationPageGeometry.canonical.height
        )
    }

    var effectiveSpreadHeightMeters: Float {
        max(spreadHeightMeters, minimumReadableHeightMeters)
    }

    func uniformScale(
        renderedBounds: SIMD3<Float>,
        targetWidthMeters: Float,
        targetHeightMeters: Float
    ) -> Float? {
        guard renderedBounds.x.isFinite,
              renderedBounds.y.isFinite,
              renderedBounds.x > 0,
              renderedBounds.y > 0,
              targetWidthMeters.isFinite,
              targetHeightMeters.isFinite,
              targetWidthMeters > 0,
              targetHeightMeters > 0
        else {
            return nil
        }

        return min(
            targetWidthMeters / renderedBounds.x,
            targetHeightMeters / renderedBounds.y
        )
    }
}
