import Foundation
@testable import LonelyPianistAVP
import simd
import Testing

@MainActor
@Test
func diskConfirmationVisibleButNoHandsNoProgress() {
    let vm = GazePlaneDiskConfirmationViewModel()
    let hit = PlaneHit(
        id: UUID(),
        hitPointWorld: SIMD3<Float>(0, 0, -1),
        planeNormalWorld: SIMD3<Float>(0, 1, 0),
        distanceMeters: 1
    )

    vm.update(planeHit: hit, leftPalmWorld: nil, rightPalmWorld: nil, nowUptime: 0)

    #expect(vm.isDiskVisible)
    #expect(vm.diskWorldTransform != nil)
    #expect(vm.isConfirmed == false)
    #expect(vm.confirmationProgress == nil)
}

@MainActor
@Test
func diskConfirmationProgressAdvancesToConfirmed() {
    let vm = GazePlaneDiskConfirmationViewModel()
    let hit = PlaneHit(
        id: UUID(),
        hitPointWorld: SIMD3<Float>(0, 0, -1),
        planeNormalWorld: SIMD3<Float>(0, 1, 0),
        distanceMeters: 1
    )

    let left = SIMD3<Float>(-0.1, 0.01, -1.05)
    let right = SIMD3<Float>(0.1, 0.01, -1.05)

    vm.update(planeHit: hit, leftPalmWorld: left, rightPalmWorld: right, nowUptime: 0)
    #expect(vm.confirmationProgress != nil)
    #expect(vm.isConfirmed == false)

    vm.update(planeHit: hit, leftPalmWorld: left, rightPalmWorld: right, nowUptime: 3.0)
    #expect(vm.isConfirmed)
    #expect(vm.confirmationProgress == 1.0)
}

@MainActor
@Test
func diskConfirmationJitterWithin3cmDoesNotReset() {
    let vm = GazePlaneDiskConfirmationViewModel()
    let hit = PlaneHit(
        id: UUID(),
        hitPointWorld: SIMD3<Float>(0, 0, -1),
        planeNormalWorld: SIMD3<Float>(0, 1, 0),
        distanceMeters: 1
    )

    let left = SIMD3<Float>(-0.1, 0.01, -1.05)
    let right = SIMD3<Float>(0.1, 0.01, -1.05)

    vm.update(planeHit: hit, leftPalmWorld: left, rightPalmWorld: right, nowUptime: 0)
    vm.update(
        planeHit: hit,
        leftPalmWorld: left + SIMD3<Float>(0.015, 0, 0),
        rightPalmWorld: right + SIMD3<Float>(0.015, 0, 0),
        nowUptime: 2.0
    )

    #expect(vm.isConfirmed == false)
    #expect((vm.confirmationProgress ?? 0) > 0.5)
}

@MainActor
@Test
func diskConfirmationJitterOver3cmResets() {
    let vm = GazePlaneDiskConfirmationViewModel()
    let hit = PlaneHit(
        id: UUID(),
        hitPointWorld: SIMD3<Float>(0, 0, -1),
        planeNormalWorld: SIMD3<Float>(0, 1, 0),
        distanceMeters: 1
    )

    let left = SIMD3<Float>(-0.1, 0.01, -1.05)
    let right = SIMD3<Float>(0.1, 0.01, -1.05)

    vm.update(planeHit: hit, leftPalmWorld: left, rightPalmWorld: right, nowUptime: 0)
    vm.update(
        planeHit: hit,
        leftPalmWorld: left + SIMD3<Float>(0.05, 0, 0),
        rightPalmWorld: right + SIMD3<Float>(0.05, 0, 0),
        nowUptime: 2.0
    )

    #expect((vm.confirmationProgress ?? 0) < 0.2)
}

@MainActor
@Test
func diskConfirmationPlaneHitNilResetsImmediately() {
    let vm = GazePlaneDiskConfirmationViewModel()
    let hit = PlaneHit(
        id: UUID(),
        hitPointWorld: SIMD3<Float>(0, 0, -1),
        planeNormalWorld: SIMD3<Float>(0, 1, 0),
        distanceMeters: 1
    )

    let left = SIMD3<Float>(-0.1, 0.01, -1.05)
    let right = SIMD3<Float>(0.1, 0.01, -1.05)

    vm.update(planeHit: hit, leftPalmWorld: left, rightPalmWorld: right, nowUptime: 0)
    vm.update(planeHit: nil, leftPalmWorld: left, rightPalmWorld: right, nowUptime: 0.1)

    #expect(vm.isDiskVisible == false)
    #expect(vm.isConfirmed == false)
    #expect(vm.confirmationProgress == nil)
}

