@testable import LonelyPianistAVP
import simd
import Testing

@Test
func keyGeometryIgnoresYNoiseInCalibrationAnchors() {
    let calibration = PianoCalibration(
        a0: SIMD3<Float>(0.0, 0.50, 0.0),
        c8: SIMD3<Float>(1.0, 1.10, 0.0),
        planeHeight: 0.50,
        frontEdgeToKeyCenterLocalZ: -PianoKeyGeometryService.whiteKeyDepthMeters / 2
    )

    let geometry = PianoKeyGeometryService().generateKeyboardGeometry(from: calibration)
    #expect(geometry?.keys.count == 88)
    #expect(abs((geometry?.frame.originWorld.y ?? -1) - 0.50) < 1e-6)
    #expect(abs(geometry?.key(for: 21)?.localCenter.x ?? -1) < 1e-6)

    let lastX = geometry?.key(for: 108)?.localCenter.x ?? -1
    #expect(abs(lastX - 1.0) < 1e-4)
}

@Test
func generateKeyboardGeometryCreatesEightyEightKeys() {
    let calibration = PianoCalibration(
        a0: SIMD3<Float>(0.0, 0.50, 0.0),
        c8: SIMD3<Float>(1.0, 0.50, 0.0),
        planeHeight: 0.50,
        whiteKeyWidth: 0.0235,
        frontEdgeToKeyCenterLocalZ: -PianoKeyGeometryService.whiteKeyDepthMeters / 2
    )

    let geometry = PianoKeyGeometryService().generateKeyboardGeometry(from: calibration)
    #expect(geometry?.keys.count == 88)
}

@Test
func keyboardGeometryCreatesFiftyTwoWhiteKeys() {
    let calibration = PianoCalibration(
        a0: SIMD3<Float>(0.0, 0.50, 0.0),
        c8: SIMD3<Float>(1.0, 0.50, 0.0),
        planeHeight: 0.50,
        frontEdgeToKeyCenterLocalZ: -PianoKeyGeometryService.whiteKeyDepthMeters / 2
    )

    let geometry = PianoKeyGeometryService().generateKeyboardGeometry(from: calibration)
    let whiteCount = geometry?.keys.count(where: { isWhite($0.kind) }) ?? 0
    let blackCount = geometry?.keys.count(where: { isBlack($0.kind) }) ?? 0
    #expect(whiteCount == 52)
    #expect(blackCount == 36)
}

@Test
func blackAndWhiteKeyKindsFollowMidiPitchClass() {
    let calibration = PianoCalibration(
        a0: SIMD3<Float>(0.0, 0.50, 0.0),
        c8: SIMD3<Float>(1.0, 0.50, 0.0),
        planeHeight: 0.50,
        frontEdgeToKeyCenterLocalZ: -PianoKeyGeometryService.whiteKeyDepthMeters / 2
    )

    let geometry = PianoKeyGeometryService().generateKeyboardGeometry(from: calibration)
    #expect(isWhite(geometry?.key(for: 60)?.kind)) // C
    #expect(isBlack(geometry?.key(for: 61)?.kind)) // C#
    #expect(isWhite(geometry?.key(for: 62)?.kind)) // D
    #expect(isBlack(geometry?.key(for: 63)?.kind)) // D#
}

@Test
func whiteKeysFollowA0ToC8WhiteKeyLayout() {
    let calibration = PianoCalibration(
        a0: SIMD3<Float>(0.0, 0.50, 0.0),
        c8: SIMD3<Float>(1.0, 0.50, 0.0),
        planeHeight: 0.50,
        frontEdgeToKeyCenterLocalZ: -PianoKeyGeometryService.whiteKeyDepthMeters / 2
    )

    let geometry = PianoKeyGeometryService().generateKeyboardGeometry(from: calibration)
    let a0 = geometry?.key(for: 21)
    let b0 = geometry?.key(for: 23)
    let c1 = geometry?.key(for: 24)
    let c8 = geometry?.key(for: 108)

    #expect(isWhite(a0?.kind))
    #expect(isWhite(b0?.kind))
    #expect(isWhite(c1?.kind))
    #expect(isWhite(c8?.kind))

    let spacing = 1.0 / Float(52 - 1)
    #expect(abs((a0?.localCenter.x ?? -1) - 0.0) < 1e-6)
    #expect(abs((b0?.localCenter.x ?? -1) - spacing) < 1e-4)
    #expect(abs((c1?.localCenter.x ?? -1) - spacing * 2) < 1e-4)
    #expect(abs((c8?.localCenter.x ?? -1) - 1.0) < 1e-4)
}

@Test
func blackKeysArePlacedBetweenAdjacentWhiteKeys() {
    let calibration = PianoCalibration(
        a0: SIMD3<Float>(0.0, 0.50, 0.0),
        c8: SIMD3<Float>(1.0, 0.50, 0.0),
        planeHeight: 0.50,
        frontEdgeToKeyCenterLocalZ: -PianoKeyGeometryService.whiteKeyDepthMeters / 2
    )

    let geometry = PianoKeyGeometryService().generateKeyboardGeometry(from: calibration)

    let a0X = geometry?.key(for: 21)?.localCenter.x ?? -1
    let b0X = geometry?.key(for: 23)?.localCenter.x ?? -1
    let aSharp0X = geometry?.key(for: 22)?.localCenter.x ?? -1

    #expect(aSharp0X > a0X)
    #expect(aSharp0X < b0X)
    #expect(abs(aSharp0X - (a0X + b0X) / 2) < 1e-4)
}

@Test
func whiteKeySurfaceIsKeyboardLocalZero() {
    let calibration = PianoCalibration(
        a0: SIMD3<Float>(0.0, 0.50, 0.0),
        c8: SIMD3<Float>(1.0, 0.50, 0.0),
        planeHeight: 0.50,
        frontEdgeToKeyCenterLocalZ: -PianoKeyGeometryService.whiteKeyDepthMeters / 2
    )

    let geometry = PianoKeyGeometryService().generateKeyboardGeometry(from: calibration)
    #expect(geometry?.key(for: 21)?.surfaceLocalY == 0)
}

@Test
func blackKeysHaveHigherSurfaceThanWhiteKeys() {
    let calibration = PianoCalibration(
        a0: SIMD3<Float>(0.0, 0.50, 0.0),
        c8: SIMD3<Float>(1.0, 0.50, 0.0),
        planeHeight: 0.50,
        frontEdgeToKeyCenterLocalZ: -PianoKeyGeometryService.whiteKeyDepthMeters / 2
    )

    let geometry = PianoKeyGeometryService().generateKeyboardGeometry(from: calibration)
    let whiteSurface = geometry?.key(for: 21)?.surfaceLocalY ?? -1
    let blackSurface = geometry?.key(for: 22)?.surfaceLocalY ?? -1
    #expect(whiteSurface == 0)
    #expect(blackSurface > whiteSurface)
}

@Test
func blackKeyFootprintsAreNarrowerAndShorterThanWhiteKeys() {
    let calibration = PianoCalibration(
        a0: SIMD3<Float>(0.0, 0.50, 0.0),
        c8: SIMD3<Float>(1.0, 0.50, 0.0),
        planeHeight: 0.50,
        frontEdgeToKeyCenterLocalZ: -PianoKeyGeometryService.whiteKeyDepthMeters / 2
    )

    let geometry = PianoKeyGeometryService().generateKeyboardGeometry(from: calibration)
    let white = geometry?.key(for: 21)
    let black = geometry?.key(for: 22)

    #expect((black?.beamFootprintSizeLocal.x ?? 100) < (white?.beamFootprintSizeLocal.x ?? -1))
    #expect((black?.beamFootprintSizeLocal.y ?? 100) < (white?.beamFootprintSizeLocal.y ?? -1))
}

@Test
func keyboardGeometryKeepsFrontEdgeSemantics() {
    let zOffset: Float = -PianoKeyGeometryService.whiteKeyDepthMeters / 2
    let calibration = PianoCalibration(
        a0: SIMD3<Float>(0.0, 0.50, 0.0),
        c8: SIMD3<Float>(1.0, 0.50, 0.0),
        planeHeight: 0.50,
        frontEdgeToKeyCenterLocalZ: zOffset
    )

    let geometry = PianoKeyGeometryService().generateKeyboardGeometry(from: calibration)
    let a0 = geometry?.key(for: 21)
    #expect(abs((a0?.localCenter.z ?? 0) - zOffset) < 1e-6)

    let calibrationFlipped = PianoCalibration(
        a0: SIMD3<Float>(0.0, 0.50, 0.0),
        c8: SIMD3<Float>(1.0, 0.50, 0.0),
        planeHeight: 0.50,
        frontEdgeToKeyCenterLocalZ: -zOffset
    )

    let geometryFlipped = PianoKeyGeometryService().generateKeyboardGeometry(from: calibrationFlipped)
    #expect(geometryFlipped?.key(for: 21)?.localCenter.x == a0?.localCenter.x)
    #expect((geometryFlipped?.key(for: 21)?.localCenter.z ?? 0) == -zOffset)
}

@Test
func keyLookupReturnsExpectedMIDINote() {
    let calibration = PianoCalibration(
        a0: SIMD3<Float>(0.0, 0.50, 0.0),
        c8: SIMD3<Float>(1.0, 0.50, 0.0),
        planeHeight: 0.50,
        frontEdgeToKeyCenterLocalZ: -PianoKeyGeometryService.whiteKeyDepthMeters / 2
    )

    let geometry = PianoKeyGeometryService().generateKeyboardGeometry(from: calibration)
    #expect(geometry?.key(for: 21)?.midiNote == 21)
    #expect(geometry?.key(for: 108)?.midiNote == 108)
}

private func isWhite(_ kind: PianoKeyKind?) -> Bool {
    guard let kind else { return false }
    if case .white = kind { return true }
    return false
}

private func isBlack(_ kind: PianoKeyKind?) -> Bool {
    guard let kind else { return false }
    if case .black = kind { return true }
    return false
}
