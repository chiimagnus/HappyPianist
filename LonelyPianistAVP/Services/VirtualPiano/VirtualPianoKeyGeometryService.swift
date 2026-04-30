import Foundation
import simd

struct VirtualPianoKeyGeometryService {
    private static let keyCount = 88
    private static let whiteKeyCount = 52
    private static let firstMIDINote = 21 // A0
    private static let lastMIDINote = 108 // C8

    static let whiteKeyWidthMeters: Float = 0.0235
    static let whiteKeySpacingMeters: Float = whiteKeyWidthMeters / 0.95
    static let totalKeyboardLengthMeters: Float = whiteKeySpacingMeters * Float(whiteKeyCount - 1)

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

        let layout = Self.makeLayoutMaps()

        var keys: [PianoKeyGeometry] = []
        keys.reserveCapacity(Self.keyCount)

        for midiNote in Self.firstMIDINote ... Self.lastMIDINote {
            let kind = Self.keyKind(for: midiNote)

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

        guard keys.count == Self.keyCount else { return nil }
        return PianoKeyboardGeometry(frame: frame, keys: keys)
    }
}

extension VirtualPianoKeyGeometryService {
    private static let blackPitchClasses: Set<Int> = [1, 3, 6, 8, 10]

    static func keyKind(for midiNote: Int) -> PianoKeyKind {
        let pitchClass = ((midiNote % 12) + 12) % 12
        return blackPitchClasses.contains(pitchClass) ? .black : .white
    }

    private struct LayoutMaps {
        let whiteKeyIndexByMIDINote: [Int: Int]
        let adjacentWhiteKeyIndicesByBlackMIDINote: [Int: (left: Int, right: Int)]
    }

    private static func makeLayoutMaps() -> LayoutMaps {
        var whiteKeyIndexByMIDINote: [Int: Int] = [:]
        var adjacentWhiteKeyIndicesByBlackMIDINote: [Int: (left: Int, right: Int)] = [:]

        var whiteIndex = 0
        var pendingBlackMIDINoteWithLeftWhiteIndex: (midi: Int, left: Int)?

        for midiNote in firstMIDINote ... lastMIDINote {
            let kind = keyKind(for: midiNote)
            switch kind {
                case .white:
                    whiteKeyIndexByMIDINote[midiNote] = whiteIndex
                    if let pending = pendingBlackMIDINoteWithLeftWhiteIndex {
                        adjacentWhiteKeyIndicesByBlackMIDINote[pending.midi] = (left: pending.left, right: whiteIndex)
                        pendingBlackMIDINoteWithLeftWhiteIndex = nil
                    }
                    whiteIndex += 1
                case .black:
                    pendingBlackMIDINoteWithLeftWhiteIndex = (midi: midiNote, left: max(0, whiteIndex - 1))
            }
        }

        return LayoutMaps(
            whiteKeyIndexByMIDINote: whiteKeyIndexByMIDINote,
            adjacentWhiteKeyIndicesByBlackMIDINote: adjacentWhiteKeyIndicesByBlackMIDINote
        )
    }
}
