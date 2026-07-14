import simd
import Testing
@testable import HappyPianistAVP

@Test
func fingerTipsSnapshotStoresTypedPositionsWithoutStringKeys() {
    let leftThumb = SIMD3<Float>(1, 2, 3)
    let rightIndex = SIMD3<Float>(4, 5, 6)
    let rightPalm = SIMD3<Float>(7, 8, 9)
    let snapshot = FingerTipsSnapshot(
        left: HandTips(thumb: leftThumb),
        right: HandTips(index: rightIndex, palm: rightPalm)
    )

    #expect(snapshot.left.thumb == leftThumb)
    #expect(snapshot.right.index == rightIndex)
    #expect(snapshot.right.palm == rightPalm)
    #expect(snapshot.left.index == nil)
}

@Test
func fingerTipsSnapshotIterationReturnsOnlyTrackedTips() {
    let snapshot = FingerTipsSnapshot(
        left: HandTips(index: SIMD3<Float>(1, 0, 0)),
        right: HandTips(middle: SIMD3<Float>(2, 0, 0))
    )
    var ids: Set<FingerTipID> = []

    snapshot.forEachTrackedTip { id, _ in
        ids.insert(id)
    }

    #expect(ids == [
        FingerTipID(hand: .left, tip: .index),
        FingerTipID(hand: .right, tip: .middle),
    ])
}
