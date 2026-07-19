import Foundation
import simd

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
