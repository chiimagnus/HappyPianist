import ARKit
import Foundation
import Practice
import MusicXML
import Diagnostics
@testable import HappyPianistAVP
import simd
import Testing

@Test
@MainActor
func beginPracticeLocalizationWithBlockingReasonTransitionsToBlocked() {
    let trackingService = FakeARTrackingService()
    let repository = InMemoryCalibrationRepository()
    let appState = AppState(
        arTrackingService: trackingService,
        calibrationCaptureService: CalibrationPointCaptureService(),
        calibrationRepository: repository,
        keyGeometryService: PianoKeyGeometryService()
    )

    let viewModel = PracticeLocalizationViewModel(
        appState: appState,
        providerStartupTimeoutSeconds: 1,
        practiceLocalizationTimeoutSeconds: 1,
        pollingInterval: .milliseconds(10)
    )

    viewModel.beginPracticeLocalization(
        isVirtualPianoEnabled: false,
        blockingReason: .missingImportedSteps
    )

    #expect(viewModel.practiceLocalizationState == .blocked(reason: .missingImportedSteps))
}

@Test
@MainActor
func shutdownCancelsProviderWaitTask() async {
    let trackingService = FakeARTrackingService()
    trackingService.isWorldTrackingSupportedOverride = true
    trackingService.providerStateByName = [
        "hand": .idle,
        "world": .idle,
    ]

    let repository = InMemoryCalibrationRepository()
    let appState = AppState(
        arTrackingService: trackingService,
        calibrationCaptureService: CalibrationPointCaptureService(),
        calibrationRepository: repository,
        keyGeometryService: PianoKeyGeometryService()
    )

    let viewModel = PracticeLocalizationViewModel(
        appState: appState,
        providerStartupTimeoutSeconds: 1,
        practiceLocalizationTimeoutSeconds: 1,
        pollingInterval: .milliseconds(20)
    )

    var failureCount = 0
    viewModel.onLocalizationFailure = { _ in failureCount += 1 }
    viewModel.beginPracticeLocalization(
        isVirtualPianoEnabled: false,
        blockingReason: nil
    )

    viewModel.shutdown()
    try? await Task.sleep(for: .milliseconds(1200))

    #expect(failureCount == 0)
    if case .failed = viewModel.practiceLocalizationState {
        #expect(Bool(false))
    }
}

@Test
@MainActor
func worldTrackingUnsupportedFailsAndNotifiesRuntimeOwner() async {
    let trackingService = FakeARTrackingService()
    trackingService.isWorldTrackingSupportedOverride = false

    let repository = InMemoryCalibrationRepository()
    let appState = AppState(
        arTrackingService: trackingService,
        calibrationCaptureService: CalibrationPointCaptureService(),
        calibrationRepository: repository,
        keyGeometryService: PianoKeyGeometryService()
    )

    let viewModel = PracticeLocalizationViewModel(
        appState: appState,
        providerStartupTimeoutSeconds: 1,
        practiceLocalizationTimeoutSeconds: 1,
        pollingInterval: .milliseconds(10)
    )

    var failures: [PracticeLocalizationViewModel.PracticeLocalizationFailure] = []
    viewModel.onLocalizationFailure = { failures.append($0) }
    viewModel.beginPracticeLocalization(
        isVirtualPianoEnabled: false,
        blockingReason: nil
    )

    try? await Task.sleep(for: .milliseconds(50))

    #expect(failures == [.worldTrackingUnsupported])
    #expect(viewModel.practiceLocalizationState == .failed(reason: .worldTrackingUnsupported))
}

@Test
@MainActor
func pausedWorldTrackingWaitsInsteadOfFailingImmediately() async {
    let trackingService = FakeARTrackingService()
    trackingService.providerStateByName = [
        "hand": .paused,
        "world": .paused,
    ]

    let appState = AppState(
        arTrackingService: trackingService,
        calibrationCaptureService: CalibrationPointCaptureService(),
        calibrationRepository: InMemoryCalibrationRepository(),
        keyGeometryService: PianoKeyGeometryService()
    )
    let viewModel = PracticeLocalizationViewModel(
        appState: appState,
        providerStartupTimeoutSeconds: 1,
        practiceLocalizationTimeoutSeconds: 1,
        pollingInterval: .milliseconds(20)
    )

    var failureCount = 0
    viewModel.onLocalizationFailure = { _ in failureCount += 1 }
    viewModel.beginPracticeLocalization(
        isVirtualPianoEnabled: false,
        blockingReason: nil
    )

    try? await Task.sleep(for: .milliseconds(80))

    #expect(viewModel.practiceLocalizationState == .waitingForProviders)
    #expect(failureCount == 0)
    viewModel.shutdown()
}

@MainActor
private final class FakeARTrackingService: ARTrackingServiceProtocol {
    var fingerTipsSnapshot = FingerTipsSnapshot.empty
    var handSkeletonSnapshot = HandSkeletonSnapshot.empty
    var worldAnchorsByID: [UUID: WorldAnchor] = [:]
    var planeAnchorsByID: [UUID: PlaneAnchor] = [:]
    var detectedPlanes: [DetectedPlane] = []
    var providerStateByName: [String: HappyPianistAVP.ARTrackingProviderState] = [
        "hand": .idle,
        "world": .idle,
        "plane": .idle,
    ]
    var worldTrackingGeneration = 0

    var isWorldTrackingSupportedOverride = true
    var isWorldTrackingSupported: Bool {
        isWorldTrackingSupportedOverride
    }

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
        nil
    }

    func addWorldAnchor(originFromAnchorTransform _: simd_float4x4) async throws -> UUID {
        UUID()
    }

    func removeWorldAnchor(id _: UUID) async throws {}

    func start(requirements _: ARTrackingRequirements) {}

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
        whiteKeyWidth: Float,
        touchCalibration: PianoTouchCalibration
    ) throws -> StoredWorldAnchorCalibration {
        let calibration = StoredWorldAnchorCalibration(
            a0AnchorID: a0AnchorID,
            c8AnchorID: c8AnchorID,
            whiteKeyWidth: whiteKeyWidth,
            touchCalibration: touchCalibration
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
