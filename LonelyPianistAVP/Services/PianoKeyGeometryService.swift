import Foundation
import simd

protocol PianoKeyGeometryServiceProtocol {
    func generateKeyRegions(from calibration: PianoCalibration) -> [PianoKeyRegion]
}

struct PianoKeyGeometryService: PianoKeyGeometryServiceProtocol {
    private let keyCount = 88
    private let firstMIDINote = 21 // A0

    // Approximate physical dimensions used for hit regions and AR highlights.
    static let keyDepthMeters: Float = 0.14
    static let keyHeightMeters: Float = 0.03

    func generateKeyRegions(from calibration: PianoCalibration) -> [PianoKeyRegion] {
        let a0World = calibration.a0.simdValue
        let c8World = calibration.c8.simdValue

        let planeY = calibration.planeHeight
        guard let frame = KeyboardFrame(a0World: a0World, c8World: c8World, planeHeight: planeY) else {
            return []
        }

        // P1 assumes the keyboard is perfectly horizontal. The keyboard frame's +X is already
        // computed from the horizontal projection of (A0 -> C8).
        let totalDistance = simd_length(SIMD3<Float>(c8World.x - a0World.x, 0, c8World.z - a0World.z))
        guard totalDistance > 0.0001 else { return [] }
        let keySpacing = totalDistance / Float(max(1, keyCount - 1))

        let depth: Float = Self.keyDepthMeters
        let height: Float = Self.keyHeightMeters
        let z = calibration.frontEdgeToKeyCenterLocalZ

        return (0 ..< keyCount).map { index in
            let midi = firstMIDINote + index
            let centerLocal = SIMD4<Float>(Float(index) * keySpacing, 0, z, 1)
            let centerWorld4 = simd_mul(frame.worldFromKeyboard, centerLocal)
            let center = SIMD3<Float>(centerWorld4.x, centerWorld4.y, centerWorld4.z)
            let width = max(0.01, calibration.whiteKeyWidth)
            return PianoKeyRegion(
                midiNote: midi,
                center: center,
                size: SIMD3<Float>(width, height, depth)
            )
        }
    }
}
