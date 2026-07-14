import simd
import Foundation

struct PianoKeyHitRegion: Equatable {
    let midiNote: Int
    let surfaceLocalY: Float
    let minX: Float
    let maxX: Float
    let minZ: Float
    let maxZ: Float
    let centerX: Float

    init(key: PianoKeyGeometry) {
        midiNote = key.midiNote
        surfaceLocalY = key.surfaceLocalY
        let halfSize = key.hitSizeLocal / 2
        minX = key.hitCenterLocal.x - halfSize.x
        maxX = key.hitCenterLocal.x + halfSize.x
        minZ = key.hitCenterLocal.z - halfSize.z
        maxZ = key.hitCenterLocal.z + halfSize.z
        centerX = key.hitCenterLocal.x
    }

    func containsXZ(_ point: SIMD3<Float>) -> Bool {
        point.x >= minX && point.x <= maxX
            && point.z >= minZ && point.z <= maxZ
    }
}

struct PianoKeyHitTestIndex {
    private let blackKeys: [PianoKeyHitRegion]
    private let whiteKeys: [PianoKeyHitRegion]

    init(keyboardGeometry: PianoKeyboardGeometry) {
        var blackKeys: [PianoKeyHitRegion] = []
        var whiteKeys: [PianoKeyHitRegion] = []
        blackKeys.reserveCapacity(36)
        whiteKeys.reserveCapacity(52)

        for key in keyboardGeometry.keys {
            let region = PianoKeyHitRegion(key: key)
            switch key.kind {
            case .black:
                blackKeys.append(region)
            case .white:
                whiteKeys.append(region)
            }
        }

        self.blackKeys = blackKeys.sorted { $0.centerX < $1.centerX }
        self.whiteKeys = whiteKeys.sorted { $0.centerX < $1.centerX }
    }

    func firstRegion(containingXZ point: SIMD3<Float>) -> PianoKeyHitRegion? {
        nearestContainingRegion(in: blackKeys, point: point)
            ?? nearestContainingRegion(in: whiteKeys, point: point)
    }

    private func nearestContainingRegion(
        in regions: [PianoKeyHitRegion],
        point: SIMD3<Float>
    ) -> PianoKeyHitRegion? {
        guard regions.isEmpty == false else { return nil }

        var lower = 0
        var upper = regions.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if regions[middle].centerX < point.x {
                lower = middle + 1
            } else {
                upper = middle
            }
        }

        // ponytail: generated piano keys can overlap only their immediate X neighbors.
        // Replace this with an interval tree only if irregular custom keyboard geometry is introduced.
        if lower < regions.count, regions[lower].containsXZ(point) {
            return regions[lower]
        }
        if lower > 0, regions[lower - 1].containsXZ(point) {
            return regions[lower - 1]
        }
        return nil
    }
}

struct PianoKeyContactTracker {
    private var cachedGeometryID: UUID?
    private var hitTestIndex: PianoKeyHitTestIndex?
    private(set) var previousDownNotes: Set<Int> = []

    mutating func reset() {
        previousDownNotes.removeAll(keepingCapacity: true)
    }

    mutating func detect(
        fingerTips: FingerTipsSnapshot,
        keyboardGeometry: PianoKeyboardGeometry,
        pressThresholdMeters: Float,
        releaseThresholdMeters: Float
    ) -> KeyContactResult {
        let index = index(for: keyboardGeometry)
        let keyboardFromWorld = keyboardGeometry.frame.keyboardFromWorld
        var currentDownNotes: Set<Int> = []
        currentDownNotes.reserveCapacity(previousDownNotes.count + 4)

        fingerTips.forEachTrackedTip { _, worldPosition in
            let localPoint = Self.transformPoint(keyboardFromWorld, worldPosition)
            guard let region = index.firstRegion(containingXZ: localPoint) else { return }

            let threshold = previousDownNotes.contains(region.midiNote)
                ? releaseThresholdMeters
                : pressThresholdMeters
            if localPoint.y <= region.surfaceLocalY + threshold {
                currentDownNotes.insert(region.midiNote)
            }
        }

        let started = currentDownNotes.subtracting(previousDownNotes)
        let ended = previousDownNotes.subtracting(currentDownNotes)
        previousDownNotes = currentDownNotes
        return KeyContactResult(down: currentDownNotes, started: started, ended: ended)
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

    @inline(__always)
    static func transformPoint(_ matrix: simd_float4x4, _ point: SIMD3<Float>) -> SIMD3<Float> {
        let value = simd_mul(matrix, SIMD4<Float>(point, 1))
        return SIMD3<Float>(value.x, value.y, value.z)
    }
}
