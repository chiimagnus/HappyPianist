import Foundation
@testable import LonelyPianistAVP
import simd
import Testing

@Test
func gazePlaneHitTestHitsHorizontalPlane() {
    let planeID = UUID()
    let planeWorldFromPlane = simd_float4x4(columns: (
        SIMD4<Float>(1, 0, 0, 0),
        SIMD4<Float>(0, 1, 0, 0),
        SIMD4<Float>(0, 0, 1, 0),
        SIMD4<Float>(0, 0, -1, 1)
    ))
    let plane = DetectedPlane(id: planeID, worldFromPlane: planeWorldFromPlane)

    let ray = GazeRay(originWorld: SIMD3<Float>(0, 1, 0), directionWorld: SIMD3<Float>(0, -1, -1))
    let service = GazePlaneHitTestService(configuration: .init(maxAngleFromUpDegrees: 10, minDistanceMeters: 0.1, maxDistanceMeters: 5))

    let hit = service.hitTest(ray: ray, planes: [plane])
    #expect(hit != nil)
    #expect(hit?.id == planeID)
    #expect(hit!.distanceMeters > 0)
}

@Test
func gazePlaneHitTestRejectsOverTiltPlane() {
    let planeID = UUID()

    // Tilt normal ~20° from up: rotate around X axis.
    let tiltDegrees: Float = 20
    let c = cos(tiltDegrees * .pi / 180)
    let s = sin(tiltDegrees * .pi / 180)
    let yAxis = SIMD4<Float>(0, c, s, 0)

    let planeWorldFromPlane = simd_float4x4(columns: (
        SIMD4<Float>(1, 0, 0, 0),
        yAxis,
        SIMD4<Float>(0, -s, c, 0),
        SIMD4<Float>(0, 0, -1, 1)
    ))
    let plane = DetectedPlane(id: planeID, worldFromPlane: planeWorldFromPlane)

    let ray = GazeRay(originWorld: SIMD3<Float>(0, 1, 0), directionWorld: SIMD3<Float>(0, -1, -1))
    let service = GazePlaneHitTestService(configuration: .init(maxAngleFromUpDegrees: 10, minDistanceMeters: 0.1, maxDistanceMeters: 5))

    let hit = service.hitTest(ray: ray, planes: [plane])
    #expect(hit == nil)
}

@Test
func gazePlaneHitTestChoosesNearestPlane() {
    let nearID = UUID()
    let farID = UUID()

    func makePlane(id: UUID, y: Float) -> DetectedPlane {
        let t = simd_float4x4(columns: (
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(0, y, 0, 1)
        ))
        return DetectedPlane(id: id, worldFromPlane: t)
    }

    let nearPlane = makePlane(id: nearID, y: 0)
    let farPlane = makePlane(id: farID, y: -1)

    let ray = GazeRay(originWorld: SIMD3<Float>(0, 1, 0), directionWorld: SIMD3<Float>(0, -1, -1))
    let service = GazePlaneHitTestService(configuration: .init(maxAngleFromUpDegrees: 10, minDistanceMeters: 0.1, maxDistanceMeters: 5))

    let hit = service.hitTest(ray: ray, planes: [farPlane, nearPlane])
    #expect(hit?.id == nearID)
}
