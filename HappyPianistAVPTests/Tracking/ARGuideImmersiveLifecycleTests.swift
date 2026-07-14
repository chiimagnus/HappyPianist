import ARKit
@testable import HappyPianistAVP
import simd
import Testing

@MainActor
@Test
func immersiveSuspendAndResumeAreIdempotentAndRebuildTrackingFromRequirements() async {
    let tracking = LifecycleTrackingService()
    let appState = AppState(arTrackingService: tracking)
    appState.immersiveMode = .calibration
    let viewModel = ARGuideViewModel(
        appState: appState,
        practiceSetupState: appState.practiceSetupState
    )

    viewModel.startTrackingIfNeeded()
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
private final class LifecycleTrackingService: ARTrackingServiceProtocol {
    var fingerTipsSnapshot = FingerTipsSnapshot.empty
    var worldAnchorsByID: [UUID: WorldAnchor] = [:]
    var planeAnchorsByID: [UUID: PlaneAnchor] = [:]
    var detectedPlanes: [DetectedPlane] = []
    var authorizationStatusByType: [ARKitSession.AuthorizationType: ARKitSession.AuthorizationStatus] = [:]
    var providerStateByName: [String: DataProviderState] = [:]
    var activeRequirements: ARTrackingRequirements = []
    var isWorldTrackingSupported = true

    private let relay = CurrentValueAsyncStreamRelay(FingerTipsSnapshot.empty)
    private(set) var startCalls: [ARTrackingRequirements] = []
    private(set) var stopCallCount = 0

    func fingerTipUpdatesStream() -> AsyncStream<FingerTipsSnapshot> {
        relay.makeStream()
    }

    func deviceWorldTransform(atTimestamp _: TimeInterval) -> simd_float4x4? { nil }

    func addWorldAnchor(originFromAnchorTransform _: simd_float4x4) async throws -> UUID {
        UUID()
    }

    func removeWorldAnchor(id _: UUID) async throws {}

    func start(requirements: ARTrackingRequirements) {
        activeRequirements = requirements
        startCalls.append(requirements)
    }

    func stop() {
        activeRequirements = []
        stopCallCount += 1
        relay.finishSubscribers()
    }
}
