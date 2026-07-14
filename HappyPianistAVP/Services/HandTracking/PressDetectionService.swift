import Foundation
import simd

protocol PressDetectionServiceProtocol {
    func detectPressedNotes(
        fingerTips: FingerTipsSnapshot,
        keyboardGeometry: PianoKeyboardGeometry?,
        at timestamp: Date
    ) -> Set<Int>
}

final class PressDetectionService: PressDetectionServiceProtocol {
    private let cooldownSeconds: TimeInterval
    private var lastFingerTips = FingerTipsSnapshot.empty
    private var lastTriggerTimeByNote: [Int: Date] = [:]
    private var cachedGeometryID: UUID?
    private var hitTestIndex: PianoKeyHitTestIndex?

    init(cooldownSeconds: TimeInterval = 0.15) {
        self.cooldownSeconds = cooldownSeconds
    }

    func detectPressedNotes(
        fingerTips: FingerTipsSnapshot,
        keyboardGeometry: PianoKeyboardGeometry?,
        at timestamp: Date
    ) -> Set<Int> {
        guard let keyboardGeometry else {
            lastFingerTips = .empty
            return []
        }

        let index = index(for: keyboardGeometry)
        let keyboardFromWorld = keyboardGeometry.frame.keyboardFromWorld
        var pressed: Set<Int> = []
        pressed.reserveCapacity(4)

        fingerTips.forEachTrackedTip { fingerID, currentPosition in
            guard let previousPosition = lastFingerTips.position(for: fingerID) else { return }

            let previousPoint = Self.transformPoint(keyboardFromWorld, previousPosition)
            let currentPoint = Self.transformPoint(keyboardFromWorld, currentPosition)
            guard let key = index.firstRegion(containingXZ: currentPoint) else { return }

            let crossedPlane = previousPoint.y > key.surfaceLocalY && currentPoint.y <= key.surfaceLocalY
            guard crossedPlane else { return }

            let isCoolingDown = lastTriggerTimeByNote[key.midiNote]
                .map { timestamp.timeIntervalSince($0) < cooldownSeconds } ?? false
            guard isCoolingDown == false else { return }

            pressed.insert(key.midiNote)
            lastTriggerTimeByNote[key.midiNote] = timestamp
        }

        lastFingerTips = fingerTips
        return pressed
    }

    private func index(for geometry: PianoKeyboardGeometry) -> PianoKeyHitTestIndex {
        if cachedGeometryID == geometry.cacheID, let hitTestIndex {
            return hitTestIndex
        }
        let next = PianoKeyHitTestIndex(keyboardGeometry: geometry)
        cachedGeometryID = geometry.cacheID
        hitTestIndex = next
        return next
    }
}

extension PressDetectionService {
    @inline(__always)
    static func transformPoint(_ matrix: simd_float4x4, _ point: SIMD3<Float>) -> SIMD3<Float> {
        let value = simd_mul(matrix, SIMD4<Float>(point, 1))
        return SIMD3<Float>(value.x, value.y, value.z)
    }
}
