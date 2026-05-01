import Foundation
import simd

struct VirtualKeyboardPoseService {
    func computeWorldFromKeyboard(
        planeWorldFromAnchor: simd_float4x4,
        handCenterOnPlaneWorld: SIMD3<Float>,
        deviceWorldTransform: simd_float4x4?
    ) -> simd_float4x4? {
        var yAxisWorld = simd_normalize(SIMD3<Float>(
            planeWorldFromAnchor.columns.1.x,
            planeWorldFromAnchor.columns.1.y,
            planeWorldFromAnchor.columns.1.z
        ))
        if simd_dot(yAxisWorld, SIMD3<Float>(0, 1, 0)) < 0 {
            yAxisWorld = -yAxisWorld
        }

        let zAxisWorld: SIMD3<Float> = {
            if let deviceWorldTransform {
                let devicePosWorld = SIMD3<Float>(deviceWorldTransform.columns.3.x, deviceWorldTransform.columns.3.y, deviceWorldTransform.columns.3.z)
                let v = devicePosWorld - handCenterOnPlaneWorld
                let vOnPlane = v - yAxisWorld * simd_dot(v, yAxisWorld)
                if simd_length(vOnPlane) > 1e-4 {
                    return simd_normalize(vOnPlane)
                }
            }

            let forward = SIMD3<Float>(
                planeWorldFromAnchor.columns.2.x,
                planeWorldFromAnchor.columns.2.y,
                planeWorldFromAnchor.columns.2.z
            )
            let forwardOnPlane = forward - yAxisWorld * simd_dot(forward, yAxisWorld)
            if simd_length(forwardOnPlane) > 1e-4 {
                return simd_normalize(forwardOnPlane)
            }

            return SIMD3<Float>(0, 0, 1)
        }()

        let xAxisWorld = simd_normalize(simd_cross(yAxisWorld, zAxisWorld))
        let zAxisOrtho = simd_normalize(simd_cross(xAxisWorld, yAxisWorld))

        if simd_length(xAxisWorld) < 1e-4 || simd_length(zAxisOrtho) < 1e-4 {
            return nil
        }

        let totalLength = VirtualPianoKeyGeometryService.totalKeyboardLengthMeters
        let keyDepth = VirtualPianoKeyGeometryService.whiteKeyDepthMeters
        let keyboardCenterLocal = SIMD3<Float>(totalLength / 2, 0, -keyDepth / 2)

        let originWorld = handCenterOnPlaneWorld
            - xAxisWorld * keyboardCenterLocal.x
            - yAxisWorld * keyboardCenterLocal.y
            - zAxisOrtho * keyboardCenterLocal.z

        return simd_float4x4(columns: (
            SIMD4<Float>(xAxisWorld, 0),
            SIMD4<Float>(yAxisWorld, 0),
            SIMD4<Float>(zAxisOrtho, 0),
            SIMD4<Float>(originWorld, 1)
        ))
    }
}
