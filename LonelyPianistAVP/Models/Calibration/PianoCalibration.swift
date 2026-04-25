import Foundation
import simd

struct CodableVector3: Codable, Equatable {
    let x: Float
    let y: Float
    let z: Float

    init(_ vector: SIMD3<Float>) {
        x = vector.x
        y = vector.y
        z = vector.z
    }

    var simdValue: SIMD3<Float> {
        SIMD3<Float>(x, y, z)
    }
}

struct PianoCalibration: Codable, Equatable {
    let a0: CodableVector3
    let c8: CodableVector3
    let planeNormal: CodableVector3
    let planeHeight: Float
    let whiteKeyWidth: Float
    /// In keyboard-local space (see `KeyboardFrame`), the calibrated A0/C8 points are interpreted as
    /// the keyboard *front edge line* (z = 0). This offset tells us where the key-center line sits
    /// along the local Z axis (typically ±keyDepth/2).
    let frontEdgeToKeyCenterLocalZ: Float
    let generatedAt: Date

    init(
        a0: SIMD3<Float>,
        c8: SIMD3<Float>,
        planeNormal: SIMD3<Float> = SIMD3<Float>(0, 1, 0),
        planeHeight: Float,
        whiteKeyWidth: Float = 0.0235,
        frontEdgeToKeyCenterLocalZ: Float = 0,
        generatedAt: Date = .now
    ) {
        self.a0 = CodableVector3(a0)
        self.c8 = CodableVector3(c8)
        self.planeNormal = CodableVector3(planeNormal)
        self.planeHeight = planeHeight
        self.whiteKeyWidth = whiteKeyWidth
        self.frontEdgeToKeyCenterLocalZ = frontEdgeToKeyCenterLocalZ
        self.generatedAt = generatedAt
    }
}
