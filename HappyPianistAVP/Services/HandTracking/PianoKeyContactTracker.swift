import Foundation
import simd

struct PianoKeyContactTracker {
    private struct ActiveContact {
        let id: PianoKeyContactID
        let midiNote: Int
        let worldPosition: SIMD3<Float>
        let planeDistanceMeters: Float
        let surfaceLocalY: Float
        let calibrationID: UUID
    }

    private var cachedGeometryID: UUID?
    private var hitTestIndex: PianoKeyHitTestIndex?
    private var activeContacts: [TrackedFingerID: ActiveContact] = [:]
    private var retriggerAllowedAt: [TrackedFingerID: PerformanceMonotonicInstant] = [:]
    private var nextSequence: UInt64 = 0

    mutating func reset() {
        activeContacts.removeAll(keepingCapacity: true)
        retriggerAllowedAt.removeAll(keepingCapacity: true)
    }

    mutating func detect(
        fingerTips: FingerTipsSnapshot,
        keyboardGeometry: PianoKeyboardGeometry,
        at timestamp: PerformanceMonotonicInstant,
        pressThresholdMeters: Float,
        releaseThresholdMeters: Float,
        retriggerDebounceSeconds: TimeInterval
    ) -> [PianoKeyContactObservation] {
        let keyboardFromWorld = keyboardGeometry.frame.keyboardFromWorld
        if let cachedGeometryID, cachedGeometryID != keyboardGeometry.cacheID {
            let ended = endAllContacts(
                fingerTips: fingerTips,
                at: timestamp,
                retriggerDebounceSeconds: retriggerDebounceSeconds
            )
            replaceIndex(for: keyboardGeometry)
            return ended
        }

        let index = index(for: keyboardGeometry)
        let previousContacts = activeContacts
        var currentContacts: [TrackedFingerID: ActiveContact] = [:]
        var observations: [PianoKeyContactObservation] = []
        currentContacts.reserveCapacity(previousContacts.count + 2)
        observations.reserveCapacity(previousContacts.count + 4)

        fingerTips.forEachFinger { fingerID, worldPosition in
            let localPoint = Self.transformPoint(keyboardFromWorld, worldPosition)
            guard let region = index.firstRegion(containingXZ: localPoint) else { return }

            let previous = previousContacts[fingerID]
            let continuesPreviousContact = previous?.midiNote == region.midiNote
                && previous?.calibrationID == keyboardGeometry.cacheID
            if previous != nil, continuesPreviousContact == false {
                return
            }

            let threshold = continuesPreviousContact ? releaseThresholdMeters : pressThresholdMeters
            guard localPoint.y <= region.surfaceLocalY + threshold else { return }
            if let allowedAt = retriggerAllowedAt[fingerID], timestamp < allowedAt, previous == nil {
                return
            }

            let contactID: PianoKeyContactID
            let phase: PianoKeyContactObservation.Phase
            if let previous {
                contactID = previous.id
                phase = .held
            } else {
                nextSequence &+= 1
                contactID = PianoKeyContactID(finger: fingerID, sequence: nextSequence)
                phase = .started
                retriggerAllowedAt.removeValue(forKey: fingerID)
            }

            let planeDistance = localPoint.y - region.surfaceLocalY
            currentContacts[fingerID] = ActiveContact(
                id: contactID,
                midiNote: region.midiNote,
                worldPosition: worldPosition,
                planeDistanceMeters: planeDistance,
                surfaceLocalY: region.surfaceLocalY,
                calibrationID: keyboardGeometry.cacheID
            )
            observations.append(
                makeObservation(
                    contactID: contactID,
                    phase: phase,
                    midiNote: region.midiNote,
                    timestamp: timestamp,
                    confidence: 1,
                    worldPosition: worldPosition,
                    planeDistanceMeters: planeDistance,
                    calibrationID: keyboardGeometry.cacheID
                )
            )
        }

        for (fingerID, previous) in previousContacts where currentContacts[fingerID]?.id != previous.id {
            observations.append(
                endObservation(
                    previous,
                    fingerID: fingerID,
                    fingerTips: fingerTips,
                    keyboardFromWorld: keyboardFromWorld,
                    at: timestamp
                )
            )
            retriggerAllowedAt[fingerID] = timestamp.advanced(by: max(0, retriggerDebounceSeconds))
        }

        activeContacts = currentContacts
        return observations.sorted(by: Self.observationOrder)
    }

    private mutating func endAllContacts(
        fingerTips: FingerTipsSnapshot,
        at timestamp: PerformanceMonotonicInstant,
        retriggerDebounceSeconds: TimeInterval
    ) -> [PianoKeyContactObservation] {
        var ended: [PianoKeyContactObservation] = []
        ended.reserveCapacity(activeContacts.count)
        for (fingerID, previous) in activeContacts {
            retriggerAllowedAt[fingerID] = timestamp.advanced(by: max(0, retriggerDebounceSeconds))
            ended.append(
                endObservation(
                    previous,
                    fingerID: fingerID,
                    fingerTips: fingerTips,
                    keyboardFromWorld: nil,
                    at: timestamp
                )
            )
        }
        activeContacts.removeAll(keepingCapacity: true)
        return ended.sorted(by: Self.observationOrder)
    }

    private func endObservation(
        _ previous: ActiveContact,
        fingerID: TrackedFingerID,
        fingerTips: FingerTipsSnapshot,
        keyboardFromWorld: simd_float4x4?,
        at timestamp: PerformanceMonotonicInstant
    ) -> PianoKeyContactObservation {
        let currentWorldPosition = fingerTips.position(for: fingerID)
        let endedWorldPosition = currentWorldPosition ?? previous.worldPosition
        let planeDistance = keyboardFromWorld.map {
            Self.transformPoint($0, endedWorldPosition).y - previous.surfaceLocalY
        } ?? previous.planeDistanceMeters
        return makeObservation(
            contactID: previous.id,
            phase: .ended,
            midiNote: previous.midiNote,
            timestamp: timestamp,
            confidence: currentWorldPosition == nil ? 0 : 1,
            worldPosition: endedWorldPosition,
            planeDistanceMeters: planeDistance,
            calibrationID: previous.calibrationID
        )
    }

    private func makeObservation(
        contactID: PianoKeyContactID,
        phase: PianoKeyContactObservation.Phase,
        midiNote: Int,
        timestamp: PerformanceMonotonicInstant,
        confidence: Float,
        worldPosition: SIMD3<Float>,
        planeDistanceMeters: Float,
        calibrationID: UUID
    ) -> PianoKeyContactObservation {
        PianoKeyContactObservation(
            id: contactID,
            phase: phase,
            keyCandidate: .exact(midiNote),
            timestamp: timestamp,
            confidence: confidence,
            worldPosition: worldPosition,
            planeDistanceMeters: planeDistanceMeters,
            normalVelocityMetersPerSecond: nil,
            calibrationID: calibrationID
        )
    }

    private mutating func index(for geometry: PianoKeyboardGeometry) -> PianoKeyHitTestIndex {
        if cachedGeometryID == geometry.cacheID, let hitTestIndex {
            return hitTestIndex
        }
        let next = PianoKeyHitTestIndex(keyboardGeometry: geometry)
        cachedGeometryID = geometry.cacheID
        hitTestIndex = next
        return next
    }

    private mutating func replaceIndex(for geometry: PianoKeyboardGeometry) {
        cachedGeometryID = geometry.cacheID
        hitTestIndex = PianoKeyHitTestIndex(keyboardGeometry: geometry)
    }

    @inline(__always)
    private static func transformPoint(_ matrix: simd_float4x4, _ point: SIMD3<Float>) -> SIMD3<Float> {
        let value = simd_mul(matrix, SIMD4<Float>(point, 1))
        return SIMD3<Float>(value.x, value.y, value.z)
    }

    private static func observationOrder(
        _ lhs: PianoKeyContactObservation,
        _ rhs: PianoKeyContactObservation
    ) -> Bool {
        if lhs.hand.rawValue != rhs.hand.rawValue { return lhs.hand.rawValue < rhs.hand.rawValue }
        if lhs.finger.rawValue != rhs.finger.rawValue { return lhs.finger.rawValue < rhs.finger.rawValue }
        return phaseOrder(lhs.phase) < phaseOrder(rhs.phase)
    }

    private static func phaseOrder(_ phase: PianoKeyContactObservation.Phase) -> Int {
        switch phase {
        case .ended: 0
        case .started: 1
        case .held: 2
        }
    }
}
