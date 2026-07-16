import ARKit
import Foundation
@testable import HappyPianistAVP
import simd
import Testing

@Test
@MainActor
func beginGuidedCalibrationSetsPendingAnchorToA0() async {
    let trackingService = FakeARTrackingService()
    let repository = InMemoryCalibrationRepository()
    let appState = AppState(
        arTrackingService: trackingService,
        calibrationCaptureService: CalibrationPointCaptureService(),
        calibrationRepository: repository,
        keyGeometryService: PianoKeyGeometryService()
    )
    appState.immersiveMode = .calibration

    let viewModel = CalibrationGuideViewModel(appState: appState)
    viewModel.beginGuidedCalibration()

    try? await Task.sleep(for: .milliseconds(10))

    #expect(appState.pendingCalibrationCaptureAnchor == .a0)
    #expect(viewModel.calibrationPhase == .capturingA0)
}

@Test
@MainActor
func presentCalibrationErrorClearsPendingAnchorAndUpdatesPhase() {
    let trackingService = FakeARTrackingService()
    let repository = InMemoryCalibrationRepository()
    let appState = AppState(
        arTrackingService: trackingService,
        calibrationCaptureService: CalibrationPointCaptureService(),
        calibrationRepository: repository,
        keyGeometryService: PianoKeyGeometryService()
    )
    appState.immersiveMode = .calibration
    appState.pendingCalibrationCaptureAnchor = .a0

    let viewModel = CalibrationGuideViewModel(appState: appState)
    viewModel.presentCalibrationError(message: "oops")

    #expect(appState.pendingCalibrationCaptureAnchor == nil)
    #expect(appState.calibrationStatusMessage == "oops")
    if case let .error(message) = viewModel.calibrationPhase {
        #expect(message == "oops")
    } else {
        #expect(Bool(false))
    }
}

@Test
@MainActor
func shutdownIsIdempotent() async {
    let trackingService = FakeARTrackingService()
    let repository = InMemoryCalibrationRepository()
    let appState = AppState(
        arTrackingService: trackingService,
        calibrationCaptureService: CalibrationPointCaptureService(),
        calibrationRepository: repository,
        keyGeometryService: PianoKeyGeometryService()
    )
    appState.immersiveMode = .calibration

    let viewModel = CalibrationGuideViewModel(appState: appState)
    viewModel.beginGuidedCalibration()

    viewModel.shutdown()
    viewModel.shutdown()

    viewModel.beginGuidedCalibration()
    try? await Task.sleep(for: .milliseconds(10))
    #expect(appState.pendingCalibrationCaptureAnchor == .a0)
}

@MainActor
private final class FakeARTrackingService: ARTrackingServiceProtocol {
    var fingerTipsSnapshot = FingerTipsSnapshot.empty
    var worldAnchorsByID: [UUID: WorldAnchor] = [:]
    var planeAnchorsByID: [UUID: PlaneAnchor] = [:]
    var detectedPlanes: [DetectedPlane] = []
    var authorizationStatusByType: [ARKitSession.AuthorizationType: ARKitSession.AuthorizationStatus] = [:]
    var providerStateByName: [String: HappyPianistAVP.ARTrackingProviderState] = [
        "hand": .idle,
        "world": .idle,
        "plane": .idle,
    ]
    var activeRequirements: ARTrackingRequirements = []

    var isWorldTrackingSupported: Bool {
        true
    }

    func fingerTipUpdatesStream() -> AsyncStream<FingerTipsSnapshot> {
        AsyncStream { continuation in
            continuation.yield(.empty)
            continuation.finish()
        }
    }

    func deviceWorldTransform(atTimestamp _: TimeInterval) -> simd_float4x4? {
        nil
    }

    func addWorldAnchor(originFromAnchorTransform _: simd_float4x4) async throws -> UUID {
        UUID()
    }

    func removeWorldAnchor(id _: UUID) async throws {}

    func start(requirements: ARTrackingRequirements) {
        activeRequirements = requirements
    }

    func stop() {}
}

@MainActor
private final class InMemoryCalibrationRepository: CalibrationRepositoryProtocol {
    private var stored: StoredWorldAnchorCalibration?

    func loadStoredCalibration() throws -> StoredWorldAnchorCalibration? {
        stored
    }

    func saveCalibration(
        a0AnchorID: UUID,
        c8AnchorID: UUID,
        whiteKeyWidth: Float
    ) throws -> StoredWorldAnchorCalibration {
        let calibration = StoredWorldAnchorCalibration(
            a0AnchorID: a0AnchorID,
            c8AnchorID: c8AnchorID,
            whiteKeyWidth: whiteKeyWidth
        )
        stored = calibration
        return calibration
    }

    func removeOldAnchorsIfPossible(
        previous _: StoredWorldAnchorCalibration,
        current _: StoredWorldAnchorCalibration,
        arTrackingService _: ARTrackingServiceProtocol
    ) async {}

    func removeCapturedAnchorsIfPossible(
        _ _: Set<UUID>,
        arTrackingService _: ARTrackingServiceProtocol
    ) async {}
}
