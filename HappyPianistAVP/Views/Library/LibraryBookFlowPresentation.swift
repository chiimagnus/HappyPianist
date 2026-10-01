import SwiftUI

struct LibraryBookFlowPresentation: Equatable {
    let yawDegrees: Double
    let scale: CGFloat
    let opacity: Double
    let lateralOffsetUnits: CGFloat
    let depthOffsetUnits: CGFloat

    init(signedDistance: CGFloat) {
        let distance = min(abs(signedDistance), 2)
        let direction: CGFloat = signedDistance < 0 ? -1 : 1

        yawDegrees = Double(-direction * min(distance, 1) * 58)
        scale = 1 - distance * 0.15
        opacity = Double(1 - distance * 0.2)
        lateralOffsetUnits = -direction * min(distance, 1) * 0.12
        depthOffsetUnits = -distance
    }
}
