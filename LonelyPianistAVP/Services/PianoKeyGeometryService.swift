import Foundation
import simd

protocol PianoKeyGeometryServiceProtocol {
    func generateKeyboardGeometry(from calibration: PianoCalibration) -> PianoKeyboardGeometry?
}

struct PianoKeyGeometryService: PianoKeyGeometryServiceProtocol {
    private static let keyCount = 88
    private static let whiteKeyCount = 52
    private static let firstMIDINote = 21 // A0
    private static let lastMIDINote = 108 // C8

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

    func generateKeyboardGeometry(from calibration: PianoCalibration) -> PianoKeyboardGeometry? {
        let a0World = calibration.a0.simdValue
        let c8World = calibration.c8.simdValue
        let planeY = calibration.planeHeight

        guard let frame = KeyboardFrame(a0World: a0World, c8World: c8World, planeHeight: planeY) else {
            return nil
        }

        let totalDistance = simd_length(SIMD3<Float>(c8World.x - a0World.x, 0, c8World.z - a0World.z))
        guard totalDistance > 0.0001 else { return nil }

        let whiteKeySpacing = totalDistance / Float(max(1, Self.whiteKeyCount - 1))
        let whiteKeyWidth = min(max(0.01, calibration.whiteKeyWidth), whiteKeySpacing * 0.95)

        let zOffset = calibration.frontEdgeToKeyCenterLocalZ
        let interiorSign: Float = abs(zOffset) > 1e-4 ? (zOffset >= 0 ? 1 : -1) : 1

        let whiteKeyCenterZ: Float = abs(zOffset) > 1e-4 ? zOffset : interiorSign * (Self.whiteKeyDepthMeters / 2)

        let layout = Self.makeLayoutMaps()

        var keys: [PianoKeyGeometry] = []
        keys.reserveCapacity(Self.keyCount)

        for midiNote in Self.firstMIDINote ... Self.lastMIDINote {
            let kind = Self.keyKind(for: midiNote)

            switch kind {
                case .white:
                    do {
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
                    }
                case .black:
                    do {
                        guard let adjacent = layout.adjacentWhiteKeyIndicesByBlackMIDINote[midiNote] else { continue }
                        let xLeft = Float(adjacent.left) * whiteKeySpacing
                        let xRight = Float(adjacent.right) * whiteKeySpacing
                        let x = (xLeft + xRight) / 2

                        let surfaceLocalY: Float = Self.blackKeySurfaceHeightMeters
                        let blackDepth = Self.whiteKeyDepthMeters * Self.blackKeyDepthScale
                        let blackWidth = whiteKeyWidth * Self.blackKeyWidthScale
                        let localSize = SIMD3<Float>(blackWidth, Self.whiteKeyThicknessMeters, blackDepth)

                        let z = interiorSign *
                            (Self.whiteKeyDepthMeters * Self.blackKeyFrontInsetScale + blackDepth / 2)
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
        }

        guard keys.count == Self.keyCount else { return nil }
        return PianoKeyboardGeometry(frame: frame, keys: keys)
    }
}

extension PianoKeyGeometryService {
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
