import Foundation
import simd

protocol VirtualPianoKeyGeometryServiceProtocol {
    func generateKeyboardGeometry(from frame: KeyboardFrame) -> PianoKeyboardGeometry?
}

struct VirtualPianoKeyGeometryService: VirtualPianoKeyGeometryServiceProtocol {
    static let whiteKeyWidthMeters: Float = 0.0235
    static let whiteKeySpacingMeters: Float = whiteKeyWidthMeters / 0.95
    static let totalKeyboardLengthMeters: Float = whiteKeySpacingMeters * Float(PianoKeyboardTopology.whiteKeyCount - 1)

    static let whiteKeyDepthMeters: Float = 0.14
    static let whiteKeyThicknessMeters: Float = 0.03

    private static let blackKeyWidthScale: Float = 0.62
    private static let blackKeyDepthScale: Float = 0.62
    private static let blackKeySurfaceHeightMeters: Float = 0.015
    private static let blackKeyFrontInsetScale: Float = 0.34

    private static let whiteBeamWidthScale: Float = 0.88
    private static let whiteBeamDepthScale: Float = 0.82
    private static let blackBeamWidthScale: Float = 0.92
    private static let blackBeamDepthScale: Float = 0.90

    func generateKeyboardGeometry(from frame: KeyboardFrame) -> PianoKeyboardGeometry? {
        let whiteKeyWidth = Self.whiteKeyWidthMeters
        let whiteKeySpacing = Self.whiteKeySpacingMeters

        // Convention for virtual keyboard geometry:
        // - Keyboard-local front edge is z = 0 (closest to the user).
        // - Keys extend "into" the keyboard along -Z.
        let whiteKeyCenterZ: Float = -Self.whiteKeyDepthMeters / 2

        let layout = PianoKeyboardTopology.layout

        var keys: [PianoKeyGeometry] = []
        keys.reserveCapacity(PianoKeyboardTopology.keyCount)

        for midiNote in PianoKeyboardTopology.playableMIDINoteRange {
            let kind = PianoKeyboardTopology.keyKind(for: midiNote)

            switch kind {
            case .white:
                guard let whiteIndex = layout.whiteKeyIndexByMIDINote[midiNote] else { continue }
                let x = Float(whiteIndex) * whiteKeySpacing

                let surfaceLocalY: Float = 0
                let localSize = SIMD3<Float>(
                    whiteKeyWidth,
                    Self.whiteKeyThicknessMeters,
                    Self.whiteKeyDepthMeters
                )
                let localCenter = SIMD3<Float>(x, surfaceLocalY - localSize.y / 2, whiteKeyCenterZ)

                let beamFootprintSizeLocal = SIMD2<Float>(
                    localSize.x * Self.whiteBeamWidthScale,
                    localSize.z * Self.whiteBeamDepthScale
                )
                let beamFootprintCenterLocal = SIMD3<Float>(x, surfaceLocalY, whiteKeyCenterZ)

                keys.append(PianoKeyGeometry(
                    midiNote: midiNote,
                    kind: kind,
                    localCenter: localCenter,
                    localSize: localSize,
                    surfaceLocalY: surfaceLocalY,
                    hitCenterLocal: localCenter,
                    hitSizeLocal: localSize,
                    beamFootprintCenterLocal: beamFootprintCenterLocal,
                    beamFootprintSizeLocal: beamFootprintSizeLocal
                ))

            case .black:
                guard let adjacent = layout.adjacentWhiteKeyIndicesByBlackMIDINote[midiNote] else { continue }
                let xLeft = Float(adjacent.left) * whiteKeySpacing
                let xRight = Float(adjacent.right) * whiteKeySpacing
                let x = (xLeft + xRight) / 2

                let surfaceLocalY: Float = Self.blackKeySurfaceHeightMeters
                let blackDepth = Self.whiteKeyDepthMeters * Self.blackKeyDepthScale
                let blackWidth = whiteKeyWidth * Self.blackKeyWidthScale
                let localSize = SIMD3<Float>(blackWidth, Self.whiteKeyThicknessMeters, blackDepth)

                let z = -(Self.whiteKeyDepthMeters * Self.blackKeyFrontInsetScale + blackDepth / 2)
                let localCenter = SIMD3<Float>(x, surfaceLocalY - localSize.y / 2, z)

                let beamFootprintSizeLocal = SIMD2<Float>(
                    localSize.x * Self.blackBeamWidthScale,
                    localSize.z * Self.blackBeamDepthScale
                )
                let beamFootprintCenterLocal = SIMD3<Float>(x, surfaceLocalY, z)

                keys.append(PianoKeyGeometry(
                    midiNote: midiNote,
                    kind: kind,
                    localCenter: localCenter,
                    localSize: localSize,
                    surfaceLocalY: surfaceLocalY,
                    hitCenterLocal: localCenter,
                    hitSizeLocal: localSize,
                    beamFootprintCenterLocal: beamFootprintCenterLocal,
                    beamFootprintSizeLocal: beamFootprintSizeLocal
                ))
            }
        }

        guard keys.count == PianoKeyboardTopology.keyCount else { return nil }
        return PianoKeyboardGeometry(frame: frame, keys: keys)
    }
}
