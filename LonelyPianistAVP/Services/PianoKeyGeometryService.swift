import Foundation
import simd

protocol PianoKeyGeometryServiceProtocol {
    func generateKeyRegions(from calibration: PianoCalibration) -> [PianoKeyRegion]
}

struct PianoKeyGeometryService: PianoKeyGeometryServiceProtocol {
    private let keyCount = 88
    private let firstMIDINote = 21 // A0

    func generateKeyRegions(from calibration: PianoCalibration) -> [PianoKeyRegion] {
        let a0 = calibration.a0.simdValue
        let c8 = calibration.c8.simdValue
        let totalDistance = simd_length(c8 - a0)
        guard totalDistance > 0.0001 else {
            return []
        }
        let axis = simd_normalize(c8 - a0)
        let keySpacing = totalDistance / Float(max(1, keyCount - 1))

        let depth: Float = 0.14
        let height: Float = 0.03
        let planeY = calibration.planeHeight

        return (0..<keyCount).map { index in
            let midi = firstMIDINote + index
            let center = a0 + axis * (Float(index) * keySpacing)
            let correctedCenter = SIMD3<Float>(center.x, planeY, center.z)
            let width = max(0.01, calibration.whiteKeyWidth)
            return PianoKeyRegion(
                midiNote: midi,
                center: correctedCenter,
                size: SIMD3<Float>(width, height, depth)
            )
        }
    }
}
