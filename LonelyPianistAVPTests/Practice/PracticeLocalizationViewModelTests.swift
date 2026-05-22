import ARKit
import Foundation
import simd
@testable import LonelyPianistAVP
import Testing

@Test
@MainActor
func beginPracticeLocalizationWithBlockingReasonTransitionsToBlocked() async {
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

    var openCallCount = 0
    await viewModel.beginPracticeLocalization(
        isVirtualPianoEnabled: false,
        blockingReason: .missingImportedSteps,
        openImmersiveSpace: { _ in .opened },
        dismissImmersiveSpace: {},
        openImmersiveForStep: { _ in
            openCallCount += 1
            return nil
        },
        closeImmersiveForStep: { dismiss in await dismiss() },
        recoverImmersiveStateIfStuck: {}
    )

    #expect(openCallCount == 0)
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

    var closeCallCount = 0
    await viewModel.beginPracticeLocalization(
        isVirtualPianoEnabled: false,
        blockingReason: nil,
        openImmersiveSpace: { _ in .opened },
        dismissImmersiveSpace: {},
        openImmersiveForStep: { _ in nil },
        closeImmersiveForStep: { dismiss in
            closeCallCount += 1
            await dismiss()
        },
        recoverImmersiveStateIfStuck: {}
    )

    viewModel.shutdown()
    try? await Task.sleep(for: .milliseconds(1200))

    #expect(closeCallCount == 0)
    if case .failed = viewModel.practiceLocalizationState {
        #expect(Bool(false))
    }
}

@Test
@MainActor
func worldTrackingUnsupportedFailsAndRequestsClose() async {
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

    var closeCallCount = 0
    await viewModel.beginPracticeLocalization(
        isVirtualPianoEnabled: false,
        blockingReason: nil,
        openImmersiveSpace: { _ in .opened },
        dismissImmersiveSpace: {},
        openImmersiveForStep: { _ in nil },
        closeImmersiveForStep: { dismiss in
            closeCallCount += 1
            await dismiss()
        },
        recoverImmersiveStateIfStuck: {}
    )

    try? await Task.sleep(for: .milliseconds(50))

    #expect(closeCallCount == 1)
    if case let .failed(reason) = viewModel.practiceLocalizationState {
        #expect(reason == .worldTrackingUnsupported)
    } else {
        #expect(Bool(false))
    }
}

@MainActor
private final class FakeARTrackingService: ARTrackingServiceProtocol {
    var fingerTipPositions: [String: SIMD3<Float>] = [:]
    var leftIndexFingerTipPosition: SIMD3<Float>?
    var leftThumbTipPosition: SIMD3<Float>?
    var rightIndexFingerTipPosition: SIMD3<Float>?
    var rightThumbTipPosition: SIMD3<Float>?
    var worldAnchorsByID: [UUID: WorldAnchor] = [:]
    var planeAnchorsByID: [UUID: PlaneAnchor] = [:]
    var authorizationStatusByType: [ARKitSession.AuthorizationType: ARKitSession.AuthorizationStatus] = [:]
    var providerStateByName: [String: LonelyPianistAVP.DataProviderState] = [
        "hand": .idle,
        "world": .idle,
    ]

    var isWorldTrackingSupportedOverride = true
    var isWorldTrackingSupported: Bool { isWorldTrackingSupportedOverride }
    let worldTrackingProvider = WorldTrackingProvider()

    func fingerTipUpdatesStream() -> AsyncStream<[String: SIMD3<Float>]> {
        AsyncStream { continuation in
            continuation.yield([:])
            continuation.finish()
        }
    }

    func start(mode _: ARTrackingMode) {}
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

