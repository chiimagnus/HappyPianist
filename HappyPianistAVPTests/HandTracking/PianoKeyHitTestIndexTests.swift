@testable import HappyPianistAVP
import simd
import Testing

@Test
func pianoKeyHitTestIndexPrefersBlackKeyWhenFootprintsOverlap() {
    let frame = KeyboardFrame(worldFromKeyboard: matrix_identity_float4x4)
    let white = makeKey(midiNote: 60, kind: .white, width: 0.04, depth: 0.14)
    let black = makeKey(midiNote: 61, kind: .black, width: 0.02, depth: 0.08)
    let index = PianoKeyHitTestIndex(
        keyboardGeometry: PianoKeyboardGeometry(frame: frame, keys: [white, black])
    )

    #expect(index.firstRegion(containingXZ: [0, 0, 0])?.midiNote == 61)
}

@Test
func pianoKeyHitTestIndexFindsAdjacentKeysAroundBinarySearchBoundary() {
    let frame = KeyboardFrame(worldFromKeyboard: matrix_identity_float4x4)
    let left = makeKey(midiNote: 60, kind: .white, centerX: -0.02, width: 0.04, depth: 0.14)
    let right = makeKey(midiNote: 62, kind: .white, centerX: 0.02, width: 0.04, depth: 0.14)
    let index = PianoKeyHitTestIndex(
        keyboardGeometry: PianoKeyboardGeometry(frame: frame, keys: [right, left])
    )

    #expect(index.firstRegion(containingXZ: [-0.019, 0, 0])?.midiNote == 60)
    #expect(index.firstRegion(containingXZ: [0.019, 0, 0])?.midiNote == 62)
}

private func makeKey(
    midiNote: Int,
    kind: PianoKeyKind,
    centerX: Float = 0,
    width: Float,
    depth: Float
) -> PianoKeyGeometry {
    PianoKeyGeometry(
        midiNote: midiNote,
        kind: kind,
        localCenter: [centerX, 0, 0],
        localSize: [width, 0.03, depth],
        surfaceLocalY: 0,
        hitCenterLocal: [centerX, 0, 0],
        hitSizeLocal: [width, 0.03, depth],
        beamFootprintCenterLocal: [centerX, 0, 0],
        beamFootprintSizeLocal: [width, depth]
    )
}
