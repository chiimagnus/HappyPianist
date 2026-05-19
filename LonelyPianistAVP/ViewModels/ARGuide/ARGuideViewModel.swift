import Foundation
import Observation
import simd
import ARKit

@MainActor
@Observable
final class ARGuideViewModel {
    typealias CalibrationPhase = CalibrationFlowViewModel.CalibrationPhase
    typealias PracticeLocalizationFailure = PracticeLocalizationViewModel.PracticeLocalizationFailure
    typealias PracticeLocalizationState = PracticeLocalizationViewModel.PracticeLocalizationState

    // MARK: - Composition root dependencies
    let appState: AppState
    let flowState: FlowState
    let pianoModeRegistry: PianoModeRegistryProtocol
    let practiceSessionViewModelFactory: PracticeSessionViewModelFactoryProtocol

    // MARK: - Child view models
    let calibrationFlowViewModel: CalibrationFlowViewModel
    let practiceLocalizationViewModel: PracticeLocalizationViewModel
    let placementViewModel: VirtualPianoPlacementViewModel
    let practiceFlowViewModel: ARGuidePracticeFlowViewModel
    let recordingViewModel: ARGuideRecordingViewModel
    let aiPerformanceViewModel: ARGuideAIPerformanceViewModel

    // MARK: - Practice session facade state
    var practiceSessionViewModel: PracticeSessionViewModel
    var latestPreparedPractice: PreparedPractice?

    @ObservationIgnored private var handTrackingConsumerTask: Task<Void, Never>?
    private var currentTrackingMode: ARTrackingMode?

    init(
        appState: AppState,
        flowState: FlowState,
        pianoModeRegistry: PianoModeRegistryProtocol,
        practiceSessionViewModelFactory: PracticeSessionViewModelFactoryProtocol,
        gazePlaneDiskConfirmation: GazePlaneDiskConfirmationViewModel? = nil,
        gazePlaneHitTestService: (any GazePlaneHitTestingProtocol)? = nil,
        virtualKeyboardPoseService: (any VirtualKeyboardPoseServiceProtocol)? = nil,
        virtualPianoKeyGeometryService: (any VirtualPianoKeyGeometryServiceProtocol)? = nil,
        backendDiscoveryService: BonjourBackendDiscoveryService? = nil,
        takeLibraryViewModel: TakeLibraryViewModel? = nil,
        takePlaybackViewModel: TakePlaybackViewModel? = nil
    ) {
        self.appState = appState
        self.flowState = flowState
        self.pianoModeRegistry = pianoModeRegistry
        self.practiceSessionViewModelFactory = practiceSessionViewModelFactory

        let initialSession = practiceSessionViewModelFactory.makePracticeSessionViewModel(for: flowState.selectedPianoModeID)
        practiceSessionViewModel = initialSession

        let calibration = CalibrationFlowViewModel(appState: appState)
        let localization = PracticeLocalizationViewModel(appState: appState)
        let placement = VirtualPianoPlacementViewModel(
            appState: appState,
            practiceSessionViewModel: initialSession,
            practiceLocalizationViewModel: localization,
            gazePlaneDiskConfirmation: gazePlaneDiskConfirmation,
            gazePlaneHitTestService: gazePlaneHitTestService,
            virtualKeyboardPoseService: virtualKeyboardPoseService,
            virtualPianoKeyGeometryService: virtualPianoKeyGeometryService
        )
        let ai = ARGuideAIPerformanceViewModel(backendDiscoveryService: backendDiscoveryService)

        calibrationFlowViewModel = calibration
        practiceLocalizationViewModel = localization
        placementViewModel = placement
        aiPerformanceViewModel = ai
        recordingViewModel = ARGuideRecordingViewModel(
            takeLibraryViewModel: takeLibraryViewModel,
            takePlaybackViewModel: takePlaybackViewModel,
            onMIDI1Event: { [weak ai] event in
                ai?.recordMIDI1EventForPhraseRecordingIfNeeded(event)
            },
            onMIDI2Event: { [weak ai] event in
                ai?.recordMIDI2EventForPhraseRecordingIfNeeded(event)
            }
        )
        practiceFlowViewModel = ARGuidePracticeFlowViewModel(
            appState: appState,
            flowState: flowState,
            practiceSessionViewModel: initialSession,
            practiceLocalizationViewModel: localization,
            placementViewModel: placement
        )

        setupAppStateCallbacks()
    }

    var selectedPianoMode: (any PianoModeProtocol)? {
        pianoModeRegistry.mode(for: flowState.selectedPianoModeID)
    }

    var isVirtualPianoMode: Bool {
        selectedPianoMode?.isVirtualPianoMode == true
    }

    var backendDiscoveryService: BonjourBackendDiscoveryService {
        aiPerformanceViewModel.backendDiscoveryService
    }

    var takeLibraryViewModel: TakeLibraryViewModel {
        recordingViewModel.takeLibraryViewModel
    }

    var takePlaybackViewModel: TakePlaybackViewModel {
        recordingViewModel.takePlaybackViewModel
    }

    var gazePlaneDiskConfirmation: GazePlaneDiskConfirmationViewModel {
        placementViewModel.gazePlaneDiskConfirmation
    }

    private func setupAppStateCallbacks() {
        flowState.onStepsImported = { [weak self] prepared in
            guard let self else { return }
            latestPreparedPractice = prepared
            applyPreparedPractice(prepared, to: practiceSessionViewModel)
            appState.applySessionIfPossible()
            if isVirtualPerformerEnabled {
                setPracticeVirtualPerformerEnabled(true)
            }
        }
        appState.onCalibrationCleared = { [weak self] in
            self?.practiceSessionViewModel.clearCalibration()
        }
        appState.onSessionReset = { [weak self] in
            self?.practiceSessionViewModel.resetSession()
        }
        appState.onApplyKeyboardGeometry = { [weak self] geometry, calibration in
            self?.practiceSessionViewModel.applyKeyboardGeometry(geometry, calibration: calibration)
        }
    }

    private func applyPreparedPractice(_ prepared: PreparedPractice, to session: PracticeSessionViewModel) {
        session.setSteps(
            prepared.steps,
            tempoMap: prepared.tempoMap,
            pedalTimeline: prepared.pedalTimeline,
            fermataTimeline: prepared.fermataTimeline,
            attributeTimeline: prepared.attributeTimeline,
            slurTimeline: prepared.slurTimeline,
            noteSpans: prepared.noteSpans,
            highlightGuides: prepared.highlightGuides,
            measureSpans: prepared.measureSpans
        )
    }

    func replacePracticeSessionViewModel() {
        let next = practiceSessionViewModelFactory.makePracticeSessionViewModel(for: flowState.selectedPianoModeID)

        practiceSessionViewModel.shutdown()
        practiceSessionViewModel = next
        placementViewModel.updatePracticeSession(next)
        practiceFlowViewModel.updatePracticeSession(next)
        aiPerformanceViewModel.updatePracticeSession(next)

        if let prepared = latestPreparedPractice {
            applyPreparedPractice(prepared, to: next)
        }

        appState.applySessionIfPossible()
        if isVirtualPianoEnabled {
            placementViewModel.setPracticeVirtualPianoEnabled(true)
        }
        if isVirtualPerformerEnabled {
            setPracticeVirtualPerformerEnabled(true)
        }

        recordingViewModel.refreshMIDISubscriptionIfNeeded(
            usesBluetoothMIDIInput: selectedPianoMode?.usesBluetoothMIDIInput == true,
            eventSource: next.practiceInputEventSource
        )
    }

    var calibration: PianoCalibration? { appState.calibration }
    var storedCalibration: StoredWorldAnchorCalibration? { appState.storedCalibration }
    var calibrationPhase: CalibrationPhase { calibrationFlowViewModel.calibrationPhase }
    var calibrationCaptureService: CalibrationPointCaptureService { appState.calibrationCaptureService }
    var arTrackingService: ARTrackingServiceProtocol { appState.arTrackingService }
    var hasImportedSteps: Bool { flowState.importedSteps.isEmpty == false }
    var immersiveMode: AppState.ImmersiveMode { appState.immersiveMode }
    var immersiveSpaceState: AppState.ImmersiveSpaceState { appState.immersiveSpaceState }

    var a0OverlayPoint: SIMD3<Float>? {
        let anchorID = calibrationCaptureService.a0AnchorID ?? storedCalibration?.a0AnchorID
        return resolvedTrackedWorldAnchorPoint(anchorID: anchorID)
    }

    var c8OverlayPoint: SIMD3<Float>? {
        let anchorID = calibrationCaptureService.c8AnchorID ?? storedCalibration?.c8AnchorID
        return resolvedTrackedWorldAnchorPoint(anchorID: anchorID)
    }

    var pendingCalibrationCaptureAnchor: CalibrationAnchorPoint? {
        get { appState.pendingCalibrationCaptureAnchor }
        set { appState.pendingCalibrationCaptureAnchor = newValue }
    }

    var calibrationStatusMessage: String? {
        get { appState.calibrationStatusMessage }
        set { appState.calibrationStatusMessage = newValue }
    }

    func saveCalibration() { _ = appState.saveCalibrationIfPossible() }
    func beginCalibrationRecapture() { appState.beginCalibrationRecapture() }
    func beginCalibrationGuidedFlow() { calibrationFlowViewModel.beginCalibrationGuidedFlow() }
    func presentCalibrationError(message: String) { calibrationFlowViewModel.presentCalibrationError(message: message) }
    func endCalibrationGuidedFlow() { calibrationFlowViewModel.endCalibrationGuidedFlow() }

    @discardableResult
    func showCalibrationCompletedIfStoredCalibrationExists() -> Bool {
        calibrationFlowViewModel.showCalibrationCompletedIfStoredCalibrationExists()
    }

    func skipStep() { practiceSessionViewModel.skip() }
    func playCurrentPracticeStepSound() { practiceSessionViewModel.playCurrentStepSound() }
    func replayCurrentPracticeUnit() { practiceSessionViewModel.replayCurrentUnit() }
    func setPracticeAutoplayEnabled(_ isEnabled: Bool) { practiceSessionViewModel.setAutoplayEnabled(isEnabled) }

    var isVirtualPianoEnabled: Bool { placementViewModel.isVirtualPianoEnabled }
    var isVirtualPianoPlaced: Bool { placementViewModel.isVirtualPianoPlaced }
    var latestDeviceWorldPosition: SIMD3<Float>? { placementViewModel.latestDeviceWorldPosition }
    var gazePlaneDiskStatusText: String? { placementViewModel.gazePlaneDiskStatusText }
    var isGazePlaneDiskVisible: Bool { placementViewModel.isGazePlaneDiskVisible }
    var gazePlaneDiskWorldTransform: simd_float4x4? { placementViewModel.gazePlaneDiskWorldTransform }
    var gazePlaneDiskOverlayText: String? { placementViewModel.gazePlaneDiskOverlayText }
    var gazePlaneDiskCameraWorldPosition: SIMD3<Float>? { placementViewModel.gazePlaneDiskCameraWorldPosition }

    func setPracticeVirtualPianoEnabled(_ isEnabled: Bool) {
        placementViewModel.setPracticeVirtualPianoEnabled(isEnabled)
    }

    func retryVirtualPianoPlacement() {
        placementViewModel.retryPlacement()
    }

    func startVirtualPianoGuidanceIfNeeded() {
        placementViewModel.startGuidanceIfNeeded()
    }

    func stopVirtualPianoGuidance() {
        placementViewModel.stopGuidance()
    }

    #if DEBUG && targetEnvironment(simulator)
        func applyVirtualPianoGeometryAtDefaultPositionForSimulator() {
            placementViewModel.applyVirtualPianoGeometryAtDefaultPositionForSimulator()
        }
    #endif

    var isVirtualPerformerEnabled: Bool { aiPerformanceViewModel.isVirtualPerformerEnabled }
    var isAIPerformanceActive: Bool { aiPerformanceViewModel.isAIPerformanceActive }
    var latestAIPerformanceSchedule: [PracticeSequencerMIDIEvent] { aiPerformanceViewModel.latestAIPerformanceSchedule }
    var lastImprovStatusText: String? { aiPerformanceViewModel.lastImprovStatusText }
    var backendStatusText: String? { aiPerformanceViewModel.backendStatusText }

    func setPracticeVirtualPerformerEnabled(_ isEnabled: Bool) {
        aiPerformanceViewModel.setVirtualPerformerEnabled(
            isEnabled,
            practiceSessionViewModel: practiceSessionViewModel
        )
    }

    var practiceLocalizationState: PracticeLocalizationState { practiceFlowViewModel.practiceLocalizationState }
    var practiceLocalizationStatusText: String? { practiceFlowViewModel.practiceLocalizationStatusText }
    var canRetryPracticeLocalization: Bool { practiceFlowViewModel.canRetryPracticeLocalization }
    var shouldSuggestCalibrationStep: Bool { practiceFlowViewModel.shouldSuggestCalibrationStep }
    var step3ARStatusText: String { practiceFlowViewModel.step3ARStatusText }
    var step3HandAssistStatusText: String { practiceFlowViewModel.step3HandAssistStatusText }
    var step3AudioStatusText: String { practiceFlowViewModel.step3AudioStatusText }
    var practiceProgressText: String { practiceFlowViewModel.practiceProgressText }

    func practiceEntryBlockingReason() -> PracticeLocalizationFailure? {
        practiceFlowViewModel.practiceEntryBlockingReason()
    }

    func enterPracticeStep(
        openImmersiveSpace: PracticeFlowOpenImmersiveSpaceHandler,
        dismissImmersiveSpace: @escaping PracticeFlowDismissImmersiveSpaceHandler
    ) async {
        await practiceFlowViewModel.enterPracticeStep(
            replacePracticeSessionViewModel: { self.replacePracticeSessionViewModel() },
            openImmersiveSpace: openImmersiveSpace,
            dismissImmersiveSpace: dismissImmersiveSpace
        )
    }

    func retryPracticeLocalization(
        openImmersiveSpace: PracticeFlowOpenImmersiveSpaceHandler,
        dismissImmersiveSpace: @escaping PracticeFlowDismissImmersiveSpaceHandler
    ) async {
        await practiceFlowViewModel.retryPracticeLocalization(
            replacePracticeSessionViewModel: { self.replacePracticeSessionViewModel() },
            openImmersiveSpace: openImmersiveSpace,
            dismissImmersiveSpace: dismissImmersiveSpace
        )
    }

    func enterVirtualPianoPlacement(openImmersiveSpace: PracticeFlowOpenImmersiveSpaceHandler) async {
        await practiceFlowViewModel.enterVirtualPianoPlacement(openImmersiveSpace: openImmersiveSpace)
    }

    func resetPracticeLocalizationState() { practiceFlowViewModel.resetPracticeLocalizationState() }

    func practiceLocalizationTimeoutFailure(
        lastRecoverableResolution: AppState.PracticeCalibrationResolutionResult?
    ) -> PracticeLocalizationFailure {
        practiceFlowViewModel.practiceLocalizationTimeoutFailure(lastRecoverableResolution: lastRecoverableResolution)
    }

    func openImmersiveForStep(
        mode: AppState.ImmersiveMode,
        openImmersiveSpace: PracticeFlowOpenImmersiveSpaceHandler
    ) async -> String? {
        await practiceFlowViewModel.openImmersiveForStep(mode: mode, openImmersiveSpace: openImmersiveSpace)
    }

    func closeImmersiveForStep(dismissImmersiveSpace: PracticeFlowDismissImmersiveSpaceHandler) async {
        await practiceFlowViewModel.closeImmersiveForStep(dismissImmersiveSpace: dismissImmersiveSpace)
    }

    func recoverImmersiveStateIfStuck() async {
        await practiceFlowViewModel.recoverImmersiveStateIfStuck()
    }

    var recordingElapsedText: String { recordingViewModel.recordingElapsedText }
    var canRecord: Bool { isVirtualPianoEnabled == false }
    var recordingSourceText: String? { selectedPianoMode?.recordingSourceText() }
    var isRecording: Bool { recordingViewModel.isRecording }
    var takeLibraryTakes: [RecordingTake] { recordingViewModel.takes }
    var takeLibraryErrorMessage: String? { recordingViewModel.errorMessage }

    func startRecording() { recordingViewModel.startRecording(canRecord: canRecord) }
    func stopRecording() { recordingViewModel.stopRecording() }
    func dismissTakeLibraryError() { recordingViewModel.dismissError() }
    func renameTake(id: UUID, name: String) { recordingViewModel.renameTake(id: id, name: name) }
    func deleteTake(id: UUID) { recordingViewModel.deleteTake(id: id) }
    func clearAllTakes() { recordingViewModel.clearAllTakes() }
    func makeMIDIExport(for take: RecordingTake) throws -> RecordingMIDIExport { try recordingViewModel.makeMIDIExport(for: take) }

    func onImmersiveAppear() {
        switch appState.immersiveMode {
            case .calibration:
                startTrackingIfNeeded()
                calibrationFlowViewModel.onImmersiveAppear()
            case .practice:
                startTrackingIfNeeded()
        }
    }

    func onImmersiveDisappear() {
        calibrationFlowViewModel.shutdown()
        practiceLocalizationViewModel.shutdown()
        practiceSessionViewModel.shutdown()
        practiceSessionViewModel.stopVirtualPianoInput()
        recordingViewModel.stop()
        aiPerformanceViewModel.shutdown()
        stopHandTracking()
    }

    func startTrackingIfNeeded() {
        let desiredMode: ARTrackingMode = switch appState.immersiveMode {
            case .calibration:
                .calibration
            case .practice:
                selectedPianoMode?.practiceTrackingMode(isVirtualPianoEnabled: isVirtualPianoEnabled) ?? .practiceVirtualOrAudio
        }

        if desiredMode != currentTrackingMode {
            stopHandTracking()
            currentTrackingMode = desiredMode
        }

        arTrackingService.start(mode: desiredMode)
        guard desiredMode != .practiceBluetoothMIDI else { return }
        guard handTrackingConsumerTask == nil else { return }

        startVirtualPianoGuidanceIfNeeded()
        let updates = arTrackingService.fingerTipUpdatesStream()
        handTrackingConsumerTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await fingerTips in updates {
                guard Task.isCancelled == false else { return }
                handleHandTrackingUpdate(fingerTips)
            }
        }
    }

    func stopHandTracking() {
        handTrackingConsumerTask?.cancel()
        handTrackingConsumerTask = nil
        currentTrackingMode = nil
        stopVirtualPianoGuidance()
        calibrationFlowViewModel.stopHandTracking()
        arTrackingService.stop()
    }

    private func handleHandTrackingUpdate(_ fingerTips: [String: SIMD3<Float>]) {
        switch appState.immersiveMode {
            case .calibration:
                calibrationFlowViewModel.handleHandUpdates()

            case .practice:
                let nowUptime = ProcessInfo.processInfo.systemUptime
                placementViewModel.updateLatestDeviceWorldPosition(nowUptime: nowUptime)
                guard isAIPerformanceActive == false else { return }

                if isVirtualPianoEnabled {
                    placementViewModel.updateGuidance(fingerTips: fingerTips, nowUptime: nowUptime)
                    if practiceSessionViewModel.keyboardGeometry != nil {
                        _ = practiceSessionViewModel.handleFingerTipPositions(fingerTips, isVirtualPiano: true)
                        recordPhraseIfNeeded(nowUptime: nowUptime)
                    }
                } else {
                    _ = practiceSessionViewModel.handleFingerTipPositions(fingerTips)
                    recordPhraseIfNeeded(nowUptime: nowUptime)
                    recordTakeIfNeeded(nowUptime: nowUptime)
                }
        }
    }

    private func recordPhraseIfNeeded(nowUptime: TimeInterval) {
        aiPerformanceViewModel.recordKeyContactForPhraseRecordingIfNeeded(
            usesBluetoothMIDIInput: selectedPianoMode?.usesBluetoothMIDIInput == true,
            keyContact: practiceSessionViewModel.latestKeyContactResult,
            nowUptimeSeconds: nowUptime
        )
    }

    private func recordTakeIfNeeded(nowUptime: TimeInterval) {
        recordingViewModel.recordTakeFromKeyContactIfNeeded(
            usesBluetoothMIDIInput: selectedPianoMode?.usesBluetoothMIDIInput == true,
            isVirtualPianoEnabled: isVirtualPianoEnabled,
            keyContact: practiceSessionViewModel.latestKeyContactResult,
            nowUptimeSeconds: nowUptime
        )
    }

    func resolvedTrackedWorldAnchorPoint(anchorID: UUID?) -> SIMD3<Float>? {
        guard let anchorID else { return nil }
        guard let anchor = arTrackingService.worldAnchorsByID[anchorID] else { return nil }
        guard anchor.isTracked else { return nil }

        let transform = anchor.originFromAnchorTransform
        return SIMD3<Float>(
            transform.columns.3.x,
            transform.columns.3.y,
            transform.columns.3.z
        )
    }

    #if DEBUG
        func setCalibrationPhaseForPreview(_ phase: CalibrationPhase) {
            calibrationFlowViewModel.setCalibrationPhaseForPreview(phase)
        }
    #endif
}
