import SwiftUI

struct LibraryBookFlowPresentation: Equatable {
    let rotationDegrees: Double
    let scale: CGFloat
    let opacity: Double
    let horizontalOffset: CGFloat
    let depthPriority: Double

    init(centerDistance: CGFloat, itemExtent: CGFloat, reduceMotion: Bool) {
        let distance = min(abs(centerDistance) / itemExtent, 2)
        let direction: CGFloat = centerDistance < 0 ? -1 : 1
        rotationDegrees = reduceMotion ? 0 : Double(-direction * min(distance, 1) * 58)
        scale = 1 - distance * 0.15
        opacity = Double(1 - distance * 0.2)
        horizontalOffset = reduceMotion ? 0 : -direction * min(distance, 1) * itemExtent * 0.12
        depthPriority = Double(2 - distance)
    }
}
