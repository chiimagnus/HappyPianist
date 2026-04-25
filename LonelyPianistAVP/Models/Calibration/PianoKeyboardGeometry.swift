import simd

enum PianoKeyKind: Equatable {
    case white
    case black
}

struct PianoKeyGeometry: Equatable, Identifiable {
    var id: Int {
        midiNote
    }

    let midiNote: Int
    let kind: PianoKeyKind

    /// Keyboard-local coordinates (see `KeyboardFrame`).
    let localCenter: SIMD3<Float>
    let localSize: SIMD3<Float>

    /// The top surface height in keyboard-local space.
    let surfaceLocalY: Float

    /// Hit-test bounds in keyboard-local space.
    let hitCenterLocal: SIMD3<Float>
    let hitSizeLocal: SIMD3<Float>

    /// Beam footprint in keyboard-local space.
    let beamFootprintCenterLocal: SIMD3<Float>
    let beamFootprintSizeLocal: SIMD2<Float>
}

struct PianoKeyboardGeometry {
    let frame: KeyboardFrame
    let keys: [PianoKeyGeometry]

    func key(for midiNote: Int) -> PianoKeyGeometry? {
        keys.first { $0.midiNote == midiNote }
    }
}
