import Foundation
import simd

protocol PressDetectionServiceProtocol {
    func detectPressedNotes(
        fingerTips: [String: SIMD3<Float>],
        keyboardGeometry: PianoKeyboardGeometry?,
        at timestamp: Date
    ) -> Set<Int>
}

final class PressDetectionService: PressDetectionServiceProtocol {
    private let cooldownSeconds: TimeInterval
    private var lastFingerTipPositions: [String: SIMD3<Float>] = [:]
    private var lastTriggerTimeByNote: [Int: Date] = [:]

    init(cooldownSeconds: TimeInterval = 0.15) {
        self.cooldownSeconds = cooldownSeconds
    }

    func detectPressedNotes(
        fingerTips: [String: SIMD3<Float>],
        keyboardGeometry: PianoKeyboardGeometry?,
        at timestamp: Date
    ) -> Set<Int> {
        guard let keyboardGeometry else { return [] }

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

        var pressed: Set<Int> = []
        let keyboardFromWorld = keyboardGeometry.frame.keyboardFromWorld

        for (fingerID, currentPosition) in fingerTips {
            defer { lastFingerTipPositions[fingerID] = currentPosition }
            guard let previousPosition = lastFingerTipPositions[fingerID] else { continue }

            let previousPoint = Self.transformPoint(keyboardFromWorld, previousPosition)
            let currentPoint = Self.transformPoint(keyboardFromWorld, currentPosition)

            for key in keysForHitTesting {
                let keyPlaneY = key.surfaceLocalY
                let crossedPlane = previousPoint.y > keyPlaneY && currentPoint.y <= keyPlaneY
                guard crossedPlane else { continue }

                let minPoint = key.hitCenterLocal - key.hitSizeLocal / 2
                let maxPoint = key.hitCenterLocal + key.hitSizeLocal / 2
                let insideKeyBounds = currentPoint.x >= minPoint.x && currentPoint.x <= maxPoint.x
                    && currentPoint.z >= minPoint.z && currentPoint.z <= maxPoint.z
                guard insideKeyBounds else { continue }

                let lastTriggerTime = lastTriggerTimeByNote[key.midiNote]
                let isCoolingDown = lastTriggerTime.map { timestamp.timeIntervalSince($0) < cooldownSeconds } ?? false
                guard isCoolingDown == false else { continue }

                pressed.insert(key.midiNote)
                lastTriggerTimeByNote[key.midiNote] = timestamp
                break
            }
        }

        return pressed
    }
}

extension PressDetectionService {
    @inline(__always)
    static func transformPoint(_ matrix: simd_float4x4, _ point: SIMD3<Float>) -> SIMD3<Float> {
        let v4 = simd_mul(matrix, SIMD4<Float>(point, 1))
        return SIMD3<Float>(v4.x, v4.y, v4.z)
    }
}
