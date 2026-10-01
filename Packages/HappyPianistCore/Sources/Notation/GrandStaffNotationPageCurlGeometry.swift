import CoreGraphics
import Foundation

struct GrandStaffNotationPageCurlGeometry: Sendable {
    let width: Double
    let height: Double
    let gutter: Double
    let progress: Double
    let forward: Bool

    var sheetWidth: Double { width + gutter / 2 }
    var spreadWidth: Double { width * 2 + gutter }
    var curvature: Double { 2 * sin(.pi * progress) }
    var rotation: Double { .pi * progress - curvature / 2 }
    var cameraDistance: Double { sheetWidth * 6 }
    var maximumScale: Double { cameraDistance / (cameraDistance - sheetWidth * sin(1)) }
    var maximumSampleOffset: CGSize {
        CGSize(width: sheetWidth * (maximumScale + 1), height: height / 2 * (maximumScale - 1))
    }
    var direction: Double { forward ? 1 : -1 }

    func projectedPoint(distance: Double, vertical: Double) -> CGPoint {
        let horizontal: Double
        let depth: Double
        if curvature < 0.0001 {
            horizontal = distance * cos(rotation)
            depth = distance * sin(rotation)
        } else {
            let radius = sheetWidth / curvature
            let angle = rotation + distance / radius
            horizontal = radius * (sin(angle) - sin(rotation))
            depth = radius * (cos(rotation) - cos(angle))
        }
        let scale = cameraDistance / (cameraDistance - depth)
        return CGPoint(x: spreadWidth / 2 + direction * horizontal * scale,
                       y: height / 2 + (vertical - height / 2) * scale)
    }
}
