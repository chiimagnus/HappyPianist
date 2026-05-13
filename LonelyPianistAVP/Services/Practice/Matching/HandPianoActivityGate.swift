import Foundation
import simd

struct HandGateState: Equatable {
    let isNearKeyboard: Bool
    let hasDownwardMotion: Bool
    let exactPressedNotes: Set<Int>
    let confidenceBoost: Double
}

final class HandPianoActivityGate {
    private let nearDistance: Float
    private let downwardThreshold: Float
    private var lastFingerTipPositions: [String: SIMD3<Float>] = [:]

    init(nearDistance: Float = 0.06, downwardThreshold: Float = 0.004) {
        self.nearDistance = nearDistance
        self.downwardThreshold = downwardThreshold
    }

    func evaluate(
        fingerTips: [String: SIMD3<Float>],
        keyboardGeometry: PianoKeyboardGeometry?,
        exactPressedNotes: Set<Int>
    ) -> HandGateState {
        guard let keyboardGeometry else {
            lastFingerTipPositions = fingerTips
            return HandGateState(
                isNearKeyboard: false,
                hasDownwardMotion: false,
                exactPressedNotes: exactPressedNotes,
                confidenceBoost: exactPressedNotes.isEmpty ? 0 : 0.10
            )
        }

        let keyboardFromWorld = keyboardGeometry.frame.keyboardFromWorld
        let yBounds = keyboardYBounds(keys: keyboardGeometry.keys)
        let xBounds = keyboardXBounds(keys: keyboardGeometry.keys)
        let zBounds = keyboardZBounds(keys: keyboardGeometry.keys)

        var isNearKeyboard = false
        var hasDownwardMotion = false

        for (fingerID, worldPoint) in fingerTips {
            let localPoint = PressDetectionService.transformPoint(keyboardFromWorld, worldPoint)
            if localPoint.y <= yBounds.upperBound + nearDistance,
               localPoint.y >= yBounds.lowerBound - nearDistance,
               localPoint.x >= xBounds.lowerBound,
               localPoint.x <= xBounds.upperBound,
               localPoint.z >= zBounds.lowerBound,
               localPoint.z <= zBounds.upperBound
            {
                isNearKeyboard = true
            }

            if let previous = lastFingerTipPositions[fingerID] {
                let previousLocal = PressDetectionService.transformPoint(keyboardFromWorld, previous)
                if previousLocal.y - localPoint.y > downwardThreshold {
                    hasDownwardMotion = true
                }
            }
        }

        lastFingerTipPositions = fingerTips

        let confidenceBoost: Double = if exactPressedNotes.isEmpty == false {
            0.10
        } else if isNearKeyboard, hasDownwardMotion {
            0.12
        } else if isNearKeyboard {
            0.06
        } else {
            0
        }

        return HandGateState(
            isNearKeyboard: isNearKeyboard,
            hasDownwardMotion: hasDownwardMotion,
            exactPressedNotes: exactPressedNotes,
            confidenceBoost: confidenceBoost
        )
    }

    func reset() {
        lastFingerTipPositions.removeAll()
    }

    private func keyboardYBounds(keys: [PianoKeyGeometry]) -> ClosedRange<Float> {
        guard keys.isEmpty == false else { return -0.02 ... 0.02 }
        let minValue = keys.map { $0.surfaceLocalY - 0.02 }.min() ?? -0.02
        let maxValue = keys.map { $0.surfaceLocalY + 0.03 }.max() ?? 0.03
        return minValue ... maxValue
    }

    private func keyboardXBounds(keys: [PianoKeyGeometry]) -> ClosedRange<Float> {
        guard keys.isEmpty == false else { return -1 ... 1 }
        let minValue = keys.map { $0.localCenter.x - $0.localSize.x / 2 }.min() ?? -1
        let maxValue = keys.map { $0.localCenter.x + $0.localSize.x / 2 }.max() ?? 1
        return minValue ... maxValue
    }

    private func keyboardZBounds(keys: [PianoKeyGeometry]) -> ClosedRange<Float> {
        guard keys.isEmpty == false else { return -1 ... 1 }
        let minValue = keys.map { $0.localCenter.z - $0.localSize.z / 2 }.min() ?? -1
        let maxValue = keys.map { $0.localCenter.z + $0.localSize.z / 2 }.max() ?? 1
        return minValue ... maxValue
    }
}
