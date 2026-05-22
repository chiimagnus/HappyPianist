@testable import LonelyPianistAVP
import simd
import Testing

@Test
func virtualPianoKeyGeometryCreatesEightyEightKeys() {
    let geometry = makeVirtualTestKeyboardGeometry()
    #expect(geometry.keys.count == 88)
}

@Test
func virtualPianoKeyboardHasFiftyTwoWhiteKeys() {
    let geometry = makeVirtualTestKeyboardGeometry()
    let whiteCount = geometry.keys.count(where: { isWhite($0.kind) })
    let blackCount = geometry.keys.count(where: { isBlack($0.kind) })
    #expect(whiteCount == 52)
    #expect(blackCount == 36)
}

@Test
func virtualPianoKeyKindsFollowMidiPitchClass() {
    let geometry = makeVirtualTestKeyboardGeometry()
    #expect(isWhite(geometry.key(for: 60)?.kind)) // C
    #expect(isBlack(geometry.key(for: 61)?.kind)) // C#
    #expect(isWhite(geometry.key(for: 62)?.kind)) // D
    #expect(isBlack(geometry.key(for: 63)?.kind)) // D#
}

@Test
func virtualWhiteKeysFollowA0ToC8WhiteKeyLayout() {
    let geometry = makeVirtualTestKeyboardGeometry()
    let a0 = geometry.key(for: 21)
    let b0 = geometry.key(for: 23)
    let c1 = geometry.key(for: 24)
    let c8 = geometry.key(for: 108)

    #expect(isWhite(a0?.kind))
    #expect(isWhite(b0?.kind))
    #expect(isWhite(c1?.kind))
    #expect(isWhite(c8?.kind))

    let spacing = VirtualPianoKeyGeometryService.whiteKeySpacingMeters
    #expect(abs((a0?.localCenter.x ?? -1) - 0.0) < 1e-6)
    #expect(abs((b0?.localCenter.x ?? -1) - spacing) < 1e-4)
    #expect(abs((c1?.localCenter.x ?? -1) - spacing * 2) < 1e-4)
    #expect(abs((c8?.localCenter.x ?? -1) - spacing * Float(52 - 1)) < 1e-4)
}

@Test
func virtualBlackKeysArePlacedBetweenAdjacentWhiteKeys() {
    let geometry = makeVirtualTestKeyboardGeometry()

    let a0X = geometry.key(for: 21)?.localCenter.x ?? -1
    let b0X = geometry.key(for: 23)?.localCenter.x ?? -1
    let aSharp0X = geometry.key(for: 22)?.localCenter.x ?? -1

    #expect(aSharp0X > a0X)
    #expect(aSharp0X < b0X)
    #expect(abs(aSharp0X - (a0X + b0X) / 2) < 1e-4)
}

private func makeVirtualTestKeyboardGeometry() -> PianoKeyboardGeometry {
    let xAxis = SIMD3<Float>(1, 0, 0)
    let yAxis = SIMD3<Float>(0, 1, 0)
    let zAxis = SIMD3<Float>(0, 0, 1)
    let origin = SIMD3<Float>(0, 0, 0)
    let transform = simd_float4x4(columns: (
        SIMD4<Float>(xAxis, 0),
        SIMD4<Float>(yAxis, 0),
        SIMD4<Float>(zAxis, 0),
        SIMD4<Float>(origin, 1)
    ))
    let frame = KeyboardFrame(worldFromKeyboard: transform)
    let service = VirtualPianoKeyGeometryService()
    return service.generateKeyboardGeometry(from: frame)!
}

private func isWhite(_ kind: PianoKeyKind?) -> Bool {
    if case .white = kind { return true }
    return false
}

private func isBlack(_ kind: PianoKeyKind?) -> Bool {
    if case .black = kind { return true }
    return false
}
