import ARKit
import Foundation
@testable import HappyPianistAVP
import simd
import Testing

@Test
func spatialLibraryPlacementUsesDeviceYawButRemainsWorldLevel() throws {
    let resolver = SpatialLibraryPlacementResolver(
        distanceMeters: 1.2,
        verticalOffsetMeters: -0.1
    )
    let position = SIMD3<Float>(0.4, 1.7, -0.3)
    let yaw: Float = .pi / 3

    let levelDevice = makeDeviceTransform(
        position: position,
        yaw: yaw,
        pitch: 0,
        roll: 0
    )
    let tiltedDevice = makeDeviceTransform(
        position: position,
        yaw: yaw,
        pitch: .pi / 5,
        roll: -.pi / 7
    )

    let level = try #require(resolver.resolve(deviceWorldTransform: levelDevice))
    let tilted = try #require(resolver.resolve(deviceWorldTransform: tiltedDevice))

    let levelX = axis(level, 0)
    let levelY = axis(level, 1)
    let levelZ = axis(level, 2)
    let tiltedX = axis(tilted, 0)
    let tiltedY = axis(tilted, 1)
    let tiltedZ = axis(tilted, 2)

    #expect(approximatelyEqual(levelY, SIMD3<Float>(0, 1, 0)))
    #expect(approximatelyEqual(tiltedY, SIMD3<Float>(0, 1, 0)))
    #expect(approximatelyEqual(levelX, tiltedX))
    #expect(approximatelyEqual(levelZ, tiltedZ))
    #expect(abs(simd_length(levelX) - 1) < 1e-5)
    #expect(abs(simd_length(levelZ) - 1) < 1e-5)
    #expect(abs(simd_dot(levelX, levelY)) < 1e-5)
    #expect(abs(simd_dot(levelY, levelZ)) < 1e-5)
    #expect(abs(simd_dot(levelX, levelZ)) < 1e-5)

    let origin = translation(level)
    #expect(abs(origin.y - 1.6) < 1e-5)

    let horizontalTowardDevice = simd_normalize(
        SIMD3<Float>(position.x - origin.x, 0, position.z - origin.z)
    )
    #expect(simd_dot(levelZ, horizontalTowardDevice) > 0.999)
    #expect(allFinite(level))
}

@Test
@MainActor
func spatialLibraryPlacementReusesWorldRootWithinSameTrackingGeneration() async throws {
    let tracking = SpatialLibraryTrackingService()
    tracking.providerStateByName["world"] = .running
    tracking.worldTrackingGeneration = 7
    tracking.deviceTransform = makeDeviceTransform(
        position: SIMD3<Float>(0, 1.6, 0),
        yaw: 0,
        pitch: 0,
        roll: 0
    )
    let viewModel = SpatialLibraryViewModel(
        arTrackingService: tracking,
        placementTimeout: .milliseconds(100),
        pollingInterval: .milliseconds(5)
    )

    viewModel.enterLibraryMode()
    await waitForPlacement(viewModel)
    let first = try #require(placedValue(viewModel.state))
    #expect(tracking.devicePoseQueryCount == 1)
    #expect(tracking.addWorldAnchorCallCount == 0)

    tracking.deviceTransform = makeDeviceTransform(
        position: SIMD3<Float>(4, 1.6, 3),
        yaw: .pi / 2,
        pitch: 0,
        roll: 0
    )
    viewModel.leaveLibraryMode()
    viewModel.enterLibraryMode()
    await Task.yield()

    let reused = try #require(placedValue(viewModel.state))
    #expect(reused == first)
    #expect(tracking.devicePoseQueryCount == 1)
    #expect(tracking.addWorldAnchorCallCount == 0)
}

@Test
@MainActor
func spatialLibraryPlacementReplacesRootAfterWorldTrackingGenerationChanges() async throws {
    let tracking = SpatialLibraryTrackingService()
    tracking.providerStateByName["world"] = .running
    tracking.worldTrackingGeneration = 2
    tracking.deviceTransform = makeDeviceTransform(
        position: SIMD3<Float>(0, 1.6, 0),
        yaw: 0,
        pitch: 0,
        roll: 0
    )
    let viewModel = SpatialLibraryViewModel(
        arTrackingService: tracking,
        placementTimeout: .milliseconds(100),
        pollingInterval: .milliseconds(5)
    )

    viewModel.enterLibraryMode()
    await waitForPlacement(viewModel)
    let first = try #require(placedValue(viewModel.state))

    viewModel.leaveLibraryMode()
    tracking.worldTrackingGeneration = 3
    tracking.deviceTransform = makeDeviceTransform(
        position: SIMD3<Float>(2, 1.8, -1),
        yaw: .pi / 2,
        pitch: 0,
        roll: 0
    )
    viewModel.enterLibraryMode()
    await waitForPlacement(viewModel)
    let replacement = try #require(placedValue(viewModel.state))

    #expect(replacement.worldTrackingGeneration == 3)
    #expect(replacement != first)
    #expect(tracking.devicePoseQueryCount == 2)
    #expect(tracking.addWorldAnchorCallCount == 0)
}

@Test
@MainActor
func spatialLibraryPlacementCanRetryAfterPoseTimeout() async throws {
    let tracking = SpatialLibraryTrackingService()
    tracking.providerStateByName["world"] = .running
    tracking.worldTrackingGeneration = 1
    let viewModel = SpatialLibraryViewModel(
        arTrackingService: tracking,
        placementTimeout: .milliseconds(20),
        pollingInterval: .milliseconds(5)
    )

    viewModel.enterLibraryMode()
    await TestAsyncWait.until(
        "Spatial Library placement timeout",
        timeout: .seconds(1),
        pollInterval: .milliseconds(2)
    ) {
        if case .placementFailed(.timedOut) = viewModel.state {
            return true
        }
        return false
    }
    #expect(viewModel.state == .placementFailed(.timedOut))

    tracking.deviceTransform = makeDeviceTransform(
        position: SIMD3<Float>(0, 1.6, 0),
        yaw: 0,
        pitch: 0,
        roll: 0
    )
    viewModel.retryPlacement()
    await waitForPlacement(viewModel)

    #expect(placedValue(viewModel.state) != nil)
    #expect(tracking.addWorldAnchorCallCount == 0)
}

@Test
@MainActor
func spatialLibraryPlacementFailsImmediatelyForUnavailableWorldProvider() async {
    let tracking = SpatialLibraryTrackingService()
    tracking.providerStateByName["world"] = .unauthorized
    let viewModel = SpatialLibraryViewModel(
        arTrackingService: tracking,
        placementTimeout: .seconds(5),
        pollingInterval: .milliseconds(250)
    )

    viewModel.enterLibraryMode()
    await TestAsyncWait.until("world authorization failure") {
        viewModel.state == .placementFailed(.worldTrackingUnauthorized)
    }

    #expect(viewModel.state == .placementFailed(.worldTrackingUnauthorized))
    #expect(tracking.devicePoseQueryCount == 0)
}

@Test
@MainActor
func arGuidePreservesLibraryPlacementAcrossModeSwitchAndInvalidatesOnSuspend() async throws {
    let tracking = SpatialLibraryTrackingService()
    tracking.providerStateByName = [
        "hand": .running,
        "world": .running,
        "plane": .disabled,
    ]
    tracking.worldTrackingGeneration = 5
    tracking.deviceTransform = makeDeviceTransform(
        position: SIMD3<Float>(0, 1.6, 0),
        yaw: 0,
        pitch: 0,
        roll: 0
    )

    let appState = AppState(arTrackingService: tracking)
    appState.immersiveMode = .library
    let spatialLibrary = SpatialLibraryViewModel(
        arTrackingService: tracking,
        placementTimeout: .milliseconds(100),
        pollingInterval: .milliseconds(5)
    )
    let viewModel = ARGuideViewModel(
        appState: appState,
        practiceSetupState: appState.practiceSetupState,
        spatialLibraryViewModel: spatialLibrary
    )

    viewModel.onImmersiveAppear()
    await waitForPlacement(spatialLibrary)
    let initial = try #require(placedValue(spatialLibrary.state))

    let open: ImmersiveSpaceOpenHandler = { _ in .opened }
    #expect(await viewModel.openImmersive(mode: .calibration, using: open) == nil)
    #expect(placedValue(spatialLibrary.state) == initial)

    #expect(await viewModel.openImmersive(mode: .library, using: open) == nil)
    await Task.yield()
    #expect(placedValue(spatialLibrary.state) == initial)
    #expect(tracking.devicePoseQueryCount == 1)

    viewModel.suspendImmersiveRuntime()
    #expect(spatialLibrary.state == .inactive)

    viewModel.resumeImmersiveRuntimeIfNeeded()
    tracking.providerStateByName["world"] = .running
    await waitForPlacement(spatialLibrary)
    #expect(placedValue(spatialLibrary.state) != nil)
    #expect(tracking.devicePoseQueryCount == 2)

    viewModel.onImmersiveDisappear()
    #expect(spatialLibrary.state == .inactive)
    #expect(tracking.addWorldAnchorCallCount == 0)
}

@MainActor
private final class SpatialLibraryTrackingService: ARTrackingServiceProtocol {
    var fingerTipsSnapshot = FingerTipsSnapshot.empty
    var handSkeletonSnapshot = HandSkeletonSnapshot.empty
    var worldAnchorsByID: [UUID: WorldAnchor] = [:]
    var planeAnchorsByID: [UUID: PlaneAnchor] = [:]
    var detectedPlanes: [DetectedPlane] = []
    var providerStateByName: [String: ARTrackingProviderState] = [
        "hand": .disabled,
        "world": .idle,
        "plane": .disabled,
    ]
    var worldTrackingGeneration = 0
    var isWorldTrackingSupported = true

    var deviceTransform: simd_float4x4?
    private(set) var devicePoseQueryCount = 0
    private(set) var addWorldAnchorCallCount = 0
    private(set) var startCalls: [ARTrackingRequirements] = []
    private(set) var stopCallCount = 0

    func fingerTipUpdatesStream() -> AsyncStream<FingerTipsSnapshot> {
        AsyncStream { continuation in
            continuation.yield(.empty)
            continuation.finish()
        }
    }

    func handSkeletonUpdatesStream() -> AsyncStream<HandSkeletonSnapshot> {
        AsyncStream { continuation in
            continuation.yield(.empty)
            continuation.finish()
        }
    }

    func deviceWorldTransform(atTimestamp _: TimeInterval) -> simd_float4x4? {
        devicePoseQueryCount += 1
        return deviceTransform
    }

    func addWorldAnchor(originFromAnchorTransform _: simd_float4x4) async throws -> UUID {
        addWorldAnchorCallCount += 1
        return UUID()
    }

    func removeWorldAnchor(id _: UUID) async throws {}

    func start(requirements: ARTrackingRequirements) {
        startCalls.append(requirements)
    }

    func stop() {
        stopCallCount += 1
    }
}

@MainActor
private func waitForPlacement(_ viewModel: SpatialLibraryViewModel) async {
    await TestAsyncWait.until(
        "Spatial Library placement",
        timeout: .seconds(1),
        pollInterval: .milliseconds(2)
    ) {
        if case .placed = viewModel.state {
            return true
        }
        return false
    }
}

private func placedValue(
    _ state: SpatialLibraryViewModel.State
) -> SpatialLibraryPlacement? {
    guard case let .placed(placement) = state else { return nil }
    return placement
}

private func makeDeviceTransform(
    position: SIMD3<Float>,
    yaw: Float,
    pitch: Float,
    roll: Float
) -> simd_float4x4 {
    let rotation =
        simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
        * simd_quatf(angle: pitch, axis: SIMD3<Float>(1, 0, 0))
        * simd_quatf(angle: roll, axis: SIMD3<Float>(0, 0, 1))
    var transform = simd_float4x4(rotation)
    transform.columns.3 = SIMD4<Float>(position, 1)
    return transform
}

private func axis(_ transform: simd_float4x4, _ index: Int) -> SIMD3<Float> {
    let column = transform[index]
    return SIMD3<Float>(column.x, column.y, column.z)
}

private func translation(_ transform: simd_float4x4) -> SIMD3<Float> {
    SIMD3<Float>(
        transform.columns.3.x,
        transform.columns.3.y,
        transform.columns.3.z
    )
}

private func approximatelyEqual(
    _ lhs: SIMD3<Float>,
    _ rhs: SIMD3<Float>,
    tolerance: Float = 1e-5
) -> Bool {
    simd_length(lhs - rhs) <= tolerance
}

private func allFinite(_ transform: simd_float4x4) -> Bool {
    (0 ..< 4).allSatisfy { index in
        let column = transform[index]
        return column.x.isFinite
            && column.y.isFinite
            && column.z.isFinite
            && column.w.isFinite
    }
}
