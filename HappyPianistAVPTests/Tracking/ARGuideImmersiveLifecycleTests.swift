import ARKit
@testable import HappyPianistAVP
import simd
import Testing

@MainActor
@Test
func immersiveSuspendAndResumeAreIdempotentAndRebuildTrackingFromRequirements() {
    let tracking = LifecycleTrackingService()
    let appState = AppState(arTrackingService: tracking)
    appState.immersiveMode = .calibration
    let viewModel = ARGuideViewModel(
        appState: appState,
        practiceSetupState: appState.practiceSetupState
    )

    viewModel.onImmersiveAppear()
    #expect(appState.immersiveSpaceState == .open)
    #expect(tracking.startCalls == [.calibration])

    viewModel.suspendImmersiveRuntime()
    viewModel.suspendImmersiveRuntime()
    #expect(tracking.stopCallCount == 1)

    viewModel.resumeImmersiveRuntimeIfNeeded()
    viewModel.resumeImmersiveRuntimeIfNeeded()
    #expect(tracking.startCalls == [.calibration, .calibration])

    viewModel.suspendImmersiveRuntime()
    #expect(tracking.stopCallCount == 2)
}

@MainActor
@Test
func mountedModeSwitchesReconcileRuntimeWithoutReopeningScene() async {
    let tracking = LifecycleTrackingService()
    tracking.providerStateByName = [
        "hand": .running,
        "world": .running,
        "plane": .disabled,
    ]
    let appState = AppState(arTrackingService: tracking)
    appState.immersiveMode = .library
    let viewModel = ARGuideViewModel(
        appState: appState,
        practiceSetupState: appState.practiceSetupState
    )

    viewModel.onImmersiveAppear()
    #expect(tracking.startCalls == [[.world]])

    var openCount = 0
    let open: ImmersiveSpaceOpenHandler = { _ in
        openCount += 1
        return .opened
    }

    #expect(await viewModel.openImmersive(mode: .calibration, using: open) == nil)
    #expect(openCount == 0)
    #expect(tracking.startCalls.last == .calibration)

    #expect(await viewModel.openImmersive(mode: .library, using: open) == nil)
    #expect(openCount == 0)
    #expect(tracking.startCalls.last == [.world])

    tracking.providerStateByName["hand"] = .unsupported
    try? await Task.sleep(for: .milliseconds(150))
    if case .error = viewModel.calibrationPhase {
        #expect(Bool(false))
    }

    tracking.providerStateByName["hand"] = .running
    #expect(await viewModel.openImmersive(mode: .practice, using: open) == nil)
    #expect(openCount == 0)
    #expect(tracking.startCalls.last == [.hand, .world])

    viewModel.onImmersiveDisappear()
}

@MainActor
private final class LifecycleTrackingService: ARTrackingServiceProtocol {
    var fingerTipsSnapshot = FingerTipsSnapshot.empty
    var handSkeletonSnapshot = HandSkeletonSnapshot.empty
    var worldAnchorsByID: [UUID: WorldAnchor] = [:]
    var planeAnchorsByID: [UUID: PlaneAnchor] = [:]
    var detectedPlanes: [DetectedPlane] = []
    var providerStateByName: [String: ARTrackingProviderState] = [:]
    var worldTrackingGeneration = 0
    var isWorldTrackingSupported = true

    private let relay = CurrentValueAsyncStreamRelay(FingerTipsSnapshot.empty)
    private let handSkeletonRelay = CurrentValueAsyncStreamRelay(HandSkeletonSnapshot.empty)
    private(set) var startCalls: [ARTrackingRequirements] = []
    private(set) var stopCallCount = 0

    func fingerTipUpdatesStream() -> AsyncStream<FingerTipsSnapshot> {
        relay.makeStream()
    }

    func handSkeletonUpdatesStream() -> AsyncStream<HandSkeletonSnapshot> {
        handSkeletonRelay.makeStream()
    }

    func deviceWorldTransform(atTimestamp _: TimeInterval) -> simd_float4x4? {
        nil
    }

    func addWorldAnchor(originFromAnchorTransform _: simd_float4x4) async throws -> UUID {
        UUID()
    }

    func removeWorldAnchor(id _: UUID) async throws {}

    func start(requirements: ARTrackingRequirements) {
        startCalls.append(requirements)
    }

    func stop() {
        stopCallCount += 1
    }
}
