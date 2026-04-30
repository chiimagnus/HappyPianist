import Foundation
import simd

struct KeyContactResult: Equatable {
    let down: Set<Int>
    let started: Set<Int>
    let ended: Set<Int>
}

@MainActor
final class KeyContactDetectionService {
    static let pressThresholdMeters: Float = 0.002
    static let releaseThresholdMeters: Float = 0.008

    private var previousDownNotes: Set<Int> = []

    func reset() {
        previousDownNotes = []
    }

    func detect(
        fingerTips: [String: SIMD3<Float>],
        keyboardGeometry: PianoKeyboardGeometry
    ) -> KeyContactResult {
        var blackKeys: [PianoKeyGeometry] = []
        var whiteKeys: [PianoKeyGeometry] = []
        blackKeys.reserveCapacity(36)
        whiteKeys.reserveCapacity(52)
        for key in keyboardGeometry.keys {
            if case .black = key.kind {
                blackKeys.append(key)
            } else {
                whiteKeys.append(key)
            }
        }
        let keysForHitTesting = blackKeys + whiteKeys

        let keyboardFromWorld = keyboardGeometry.frame.keyboardFromWorld
        var currentDownNotes: Set<Int> = []

        for (_, worldPosition) in fingerTips {
            let localPoint = Self.transformPoint(keyboardFromWorld, worldPosition)

            for key in keysForHitTesting {
                let minPoint = key.hitCenterLocal - key.hitSizeLocal / 2
                let maxPoint = key.hitCenterLocal + key.hitSizeLocal / 2
                let insideBounds = localPoint.x >= minPoint.x && localPoint.x <= maxPoint.x
                    && localPoint.z >= minPoint.z && localPoint.z <= maxPoint.z
                guard insideBounds else { continue }

                let wasDown = previousDownNotes.contains(key.midiNote)
                if wasDown {
                    if localPoint.y <= key.surfaceLocalY + Self.releaseThresholdMeters {
                        currentDownNotes.insert(key.midiNote)
                    }
                } else {
                    if localPoint.y <= key.surfaceLocalY + Self.pressThresholdMeters {
                        currentDownNotes.insert(key.midiNote)
                    }
                }
            }
        }

        let started = currentDownNotes.subtracting(previousDownNotes)
        let ended = previousDownNotes.subtracting(currentDownNotes)
        previousDownNotes = currentDownNotes

        return KeyContactResult(down: currentDownNotes, started: started, ended: ended)
    }

    @inline(__always)
    private static func transformPoint(_ matrix: simd_float4x4, _ point: SIMD3<Float>) -> SIMD3<Float> {
        let v4 = simd_mul(matrix, SIMD4<Float>(point, 1))
        return SIMD3<Float>(v4.x, v4.y, v4.z)
    }
}
