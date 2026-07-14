import ARKit
import Foundation
import Observation
import simd

@MainActor
@Observable
final class ARGuideViewModel {
    typealias CalibrationPhase = CalibrationGuideViewModel.CalibrationPhase
    typealias PracticeLocalizationFailure = PracticeLocalizationViewModel.PracticeLocalizationFailure
    typealias PracticeLocalizationState = PracticeLocalizationViewModel.PracticeLocalizationState

    // MARK: - App-level dependencies

    let appState: AppState
    let practiceSetupState: PracticeSetupState
    let pianoModeRegistry: PianoModeRegistryProtocol
    private let makePracticeSessionViewModel: @MainActor (String?) -> PracticeSessionViewModel

    // MARK: - Child view models

    let calibrationGuideViewModel: CalibrationGuideViewModel
    let practiceLocalizationViewModel: PracticeLocalizationViewModel
    let placementViewModel: VirtualPianoPlacementViewModel
    let practiceViewModel: ARGuidePracticeViewModel
    let recordingViewModel: ARGuideRecordingViewModel
    let aiPerformanceViewModel: ARGuideAIPerformanceViewModel
    let practiceFeedbackViewModel = PracticeFeedbackViewModel()

    // MARK: - Practice session facade state

    var practiceSessionViewModel: PracticeSessionViewModel
    var latestPreparedPractice: PreparedPractice?

    @ObservationIgnored private var handTrackingConsumerTask: Task<Void, Never>?
    @ObservationIgnored private var preparedPracticeApplicationID: UUID?
    @ObservationIgnored private var currentTrackingRequirements: ARTrackingRequirements = []
    @ObservationIgnored private var isImmersiveRuntimeSuspended = false
    @ObservationIgnored private var shouldResumeVirtualPerformer = false

    init(
        appState: AppState,
        practiceSetupState: PracticeSetupState,
        pianoModeRegistry: PianoModeRegistryProtocol,
        makePracticeSessionViewModel: @escaping @MainActor (String?) -> PracticeSessionViewModel,
        gazePlaneDiskConfirmation: GazePlaneDiskConfirmationViewModel? = nil,
        gazePlaneHitTestService: (any GazePlaneHitTestingProtocol)? = nil,
        virtualKeyboardPoseService: (any VirtualKeyboardPoseServiceProtocol)? = nil,
        virtualPianoKeyGeometryService: (any VirtualPianoKeyGeometryServiceProtocol)? = nil,
        aiPlaybackServiceFactory: (@MainActor () -> DuetAIPlaybackServiceFactory)? = nil,
        takeLibraryViewModel: TakeLibraryViewModel? = nil,
        takePlaybackViewModel: TakePlaybackViewModel? = nil
    ) {
        self.appState = appState
        self.practiceSetupState = practiceSetupState
        self.pianoModeRegistry = pianoModeRegistry
        self.makePracticeSessionViewModel = makePracticeSessionViewModel

        let initialSession = makePracticeSessionViewModel(practiceSetupState.selectedPianoModeID)
        practiceSessionViewModel = initialSession

        let calibration = CalibrationGuideViewModel(appState: appState)
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
        let ai = ARGuideAIPerformanceViewModel(
            aiPlaybackServiceFactory: aiPlaybackServiceFactory
        )

        calibrationGuideViewModel = calibration
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
        practiceViewModel = ARGuidePracticeViewModel(
            appState: appState,
            practiceSetupState: practiceSetupState,
            practiceSessionViewModel: initialSession,
            practiceLocalizationViewModel: localization,
            placementViewModel: placement
        )

        placement.onTrackingRequirementsChanged = { [weak self] in
            self?.startTrackingIfNeeded()
        }
        setupAppStateCallbacks()

        // Ensure Bluetooth MIDI input events are subscribed immediately for the initial practice session.
        // Otherwise, AI improv (and recording) won't receive any MIDI events until the session is rebuilt.
        recordingViewModel.refreshMIDISubscriptionIfNeeded(
            usesBluetoothMIDIInput: PianoModeID(rawValue: practiceSetupState.selectedPianoModeID ?? "") == .bluetoothMIDI,
            eventSource: initialSession.practiceInputEventSource
        )
    }

    var selectedPianoMode: (any PianoModeProtocol)? {
        pianoModeRegistry.mode(for: practiceSetupState.selectedPianoModeID)
    }

    var isVirtualPianoMode: Bool {
        selectedPianoMode?.isVirtualPianoMode == true
    }

    var isBluetoothMIDIMode: Bool {
        PianoModeID(rawValue: practiceSetupState.selectedPianoModeID ?? "") == .bluetoothMIDI
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
        appState.onCalibrationCleared = { [weak self] in
            self?.practiceSessionViewModel.clearCalibration()
        }
        appState.onSessionReset = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                await self.practiceSessionViewModel.suspendAndFlushProgress()
                self.practiceSessionViewModel.resetSession()
            }
        }
        appState.onApplyKeyboardGeometry = { [weak self] geometry, calibration in
            self?.practiceSessionViewModel.applyKeyboardGeometry(geometry, calibration: calibration)
        }
    }

    @discardableResult
    func applyPreparedPractice(
        _ prepared: PreparedPractice,
        isCurrent: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let applicationID = UUID()
        preparedPracticeApplicationID = applicationID
        guard isCurrent() else {
            preparedPracticeApplicationID = nil
            return false
        }
        guard await applyPreparedPractice(
            prepared,
            to: practiceSessionViewModel,
            applicationID: applicationID,
            isCurrent: isCurrent
        ) else { return false }

        practiceSetupState.setImportedSteps(from: prepared)
        appState.applySessionIfPossible()
        latestPreparedPractice = prepared
        preparedPracticeApplicationID = nil
        if isVirtualPerformerEnabled {
            setPracticeVirtualPerformerEnabled(true)
        }
        return true
    }

    private func applyPreparedPractice(
        _ prepared: PreparedPractice,
        to session: PracticeSessionViewModel,
        applicationID: UUID,
        isCurrent: @escaping @MainActor () -> Bool
    ) async -> Bool {
        guard preparedPracticeApplicationID == applicationID, isCurrent() else { return false }
        session.installPreparedSteps(
            prepared.steps,
            identity: prepared.identity,
            tempoMap: prepared.tempoMap,
            pedalTimeline: prepared.pedalTimeline,
            fermataTimeline: prepared.fermataTimeline,
            attributeTimeline: prepared.attributeTimeline,
            highlightGuides: prepared.highlightGuides,
            measureSpans: prepared.measureSpans
        )
        guard preparedPracticeApplicationID == applicationID, isCurrent() else {
            clearStalePreparedPractice(applicationID: applicationID, session: session)
            return false
        }
        await session.restoreProgressIfAvailable()
        guard preparedPracticeApplicationID == applicationID, isCurrent() else {
            clearStalePreparedPractice(applicationID: applicationID, session: session)
            return false
        }
        return true
    }

    private func clearStalePreparedPractice(
        applicationID: UUID,
        session: PracticeSessionViewModel
    ) {
        guard preparedPracticeApplicationID == applicationID else { return }
        session.resetSession()
        preparedPracticeApplicationID = nil
    }

    func replacePracticeSessionViewModel() async {
        await practiceSessionViewModel.flushAndShutdown()
        let next = makePracticeSessionViewModel(practiceSetupState.selectedPianoModeID)
        practiceSessionViewModel = next
        placementViewModel.updatePracticeSession(next)
        practiceViewModel.updatePracticeSession(next)
        aiPerformanceViewModel.updatePracticeSession(next)

        if let prepared = latestPreparedPractice {
            let applicationID = UUID()
            preparedPracticeApplicationID = applicationID
            _ = await applyPreparedPractice(
                prepared,
                to: next,
                applicationID: applicationID,
                isCurrent: { true }
            )
            preparedPracticeApplicationID = nil
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

    var calibration: PianoCalibration? {
        appState.calibration
    }

    var storedCalibration: StoredWorldAnchorCalibration? {
        appState.storedCalibration
    }

    var calibrationPhase: CalibrationPhase {
        calibrationGuideViewModel.calibrationPhase
    }

    var calibrationCaptureService: CalibrationPointCaptureService {
        appState.calibrationCaptureService
    }

    var arTrackingService: ARTrackingServiceProtocol {
        appState.arTrackingService
    }

    var hasImportedSteps: Bool {
        practiceSetupState.importedSteps.isEmpty == false
    }

    var immersiveMode: AppState.ImmersiveMode {
        appState.immersiveMode
    }

    var immersiveSpaceState: AppState.ImmersiveSpaceState {
        appState.immersiveSpaceState
    }

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

    func saveCalibration() {
        _ = appState.saveCalibrationIfPossible()
    }

    func beginCalibrationRecapture() {
        appState.beginCalibrationRecapture()
    }

    func beginGuidedCalibration() {
        calibrationGuideViewModel.beginGuidedCalibration()
    }

    func presentCalibrationError(message: String) {
        calibrationGuideViewModel.presentCalibrationError(message: message)
    }

    func endGuidedCalibration() {
        calibrationGuideViewModel.endGuidedCalibration()
    }

    @discardableResult
    func showCalibrationCompletedIfStoredCalibrationExists() -> Bool {
        calibrationGuideViewModel.showCalibrationCompletedIfStoredCalibrationExists()
    }

    func skipStep() {
        practiceSessionViewModel.skip()
    }

    func playCurrentPracticeStepSound() {
        practiceSessionViewModel.playCurrentStepSound()
    }

    func replayCurrentPracticeUnit() {
        practiceSessionViewModel.replayCurrentUnit()
    }

    func setPracticeAutoplayEnabled(_ isEnabled: Bool) {
        practiceSessionViewModel.setAutoplayEnabled(isEnabled)
    }

    var isVirtualPianoEnabled: Bool {
        placementViewModel.isVirtualPianoEnabled
    }

    var shouldShowVirtualPiano: Bool {
        placementViewModel.isVirtualPianoEnabled && placementViewModel.presentation != .hidden
    }

    var isVirtualPianoPlaced: Bool {
        placementViewModel.isVirtualPianoPlaced
    }

    var gazePlaneDiskStatusText: String? {
        placementViewModel.gazePlaneDiskStatusText
    }

    var isGazePlaneDiskVisible: Bool {
        placementViewModel.isGazePlaneDiskVisible
    }

    var gazePlaneDiskWorldTransform: simd_float4x4? {
        placementViewModel.gazePlaneDiskWorldTransform
    }

    var gazePlaneDiskOverlayText: String? {
        placementViewModel.gazePlaneDiskOverlayText
    }

    var gazePlaneDiskCameraWorldPosition: SIMD3<Float>? {
        placementViewModel.gazePlaneDiskCameraWorldPosition
    }

    func setPracticeVirtualPianoEnabled(_ isEnabled: Bool) {
        placementViewModel.setPracticeVirtualPianoEnabled(isEnabled)
    }

    func hideVirtualPiano() {
        placementViewModel.hideVirtualPiano()
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

    var isVirtualPerformerEnabled: Bool {
        aiPerformanceViewModel.isVirtualPerformerEnabled
    }

    var isAIPerformanceActive: Bool {
        aiPerformanceViewModel.isAIPerformanceActive
    }

    var latestAIPerformanceSchedule: [PracticeSequencerMIDIEvent] {
        aiPerformanceViewModel.latestAIPerformanceSchedule
    }

    var lastImprovStatusText: String? {
        aiPerformanceViewModel.lastImprovStatusText
    }

    var backendStatusText: String? {
        aiPerformanceViewModel.backendStatusText
    }

    func setPracticeVirtualPerformerEnabled(_ isEnabled: Bool) {
        aiPerformanceViewModel.setVirtualPerformerEnabled(
            isEnabled,
            practiceSessionViewModel: practiceSessionViewModel
        )
    }

    #if DEBUG
        func debugInjectAIImprovPhrase() {
            aiPerformanceViewModel.debugInjectImprovTestPhraseIfPossible()
        }
    #endif

    var practiceLocalizationState: PracticeLocalizationState {
        practiceViewModel.practiceLocalizationState
    }

    var practiceLocalizationStatusText: String? {
        practiceViewModel.practiceLocalizationStatusText
    }

    var canRetryPracticeLocalization: Bool {
        practiceViewModel.canRetryPracticeLocalization
    }

    var shouldSuggestCalibrationStep: Bool {
        practiceViewModel.shouldSuggestCalibrationStep
    }

    var step3ARStatusText: String {
        practiceViewModel.step3ARStatusText
    }

    var step3HandAssistStatusText: String {
        practiceViewModel.step3HandAssistStatusText
    }

    var step3AudioStatusText: String {
        practiceViewModel.step3AudioStatusText
    }

    var practiceProgressText: String {
        practiceViewModel.practiceProgressText
    }

    func practiceEntryBlockingReason() -> PracticeLocalizationFailure? {
        practiceViewModel.practiceEntryBlockingReason()
    }

    func enterPracticeStep(
        openImmersiveSpace: PracticeImmersiveOpenHandler,
        dismissImmersiveSpace: @escaping PracticeImmersiveDismissHandler
    ) async {
        await practiceViewModel.enterPracticeStep(
            openImmersiveSpace: openImmersiveSpace,
            dismissImmersiveSpace: dismissImmersiveSpace
        )
    }

    func retryPracticeLocalization(
        openImmersiveSpace: PracticeImmersiveOpenHandler,
        dismissImmersiveSpace: @escaping PracticeImmersiveDismissHandler
    ) async {
        await practiceViewModel.retryPracticeLocalization(
            openImmersiveSpace: openImmersiveSpace,
            dismissImmersiveSpace: dismissImmersiveSpace
        )
    }

    func enterVirtualPianoPlacement(openImmersiveSpace: PracticeImmersiveOpenHandler) async {
        await practiceViewModel.enterVirtualPianoPlacement(openImmersiveSpace: openImmersiveSpace)
    }

    func resetPracticeLocalizationState() {
        practiceViewModel.resetPracticeLocalizationState()
    }

    func practiceLocalizationTimeoutFailure(
        lastRecoverableResolution: AppState.PracticeCalibrationResolutionResult?
    ) -> PracticeLocalizationFailure {
        practiceViewModel.practiceLocalizationTimeoutFailure(lastRecoverableResolution: lastRecoverableResolution)
    }

    func openImmersiveForStep(
        mode: AppState.ImmersiveMode,
        openImmersiveSpace: PracticeImmersiveOpenHandler
    ) async -> String? {
        await practiceViewModel.openImmersiveForStep(mode: mode, openImmersiveSpace: openImmersiveSpace)
    }

    func closeImmersiveForStep(dismissImmersiveSpace: PracticeImmersiveDismissHandler) async {
        await practiceViewModel.closeImmersiveForStep(dismissImmersiveSpace: dismissImmersiveSpace)
    }

    func recoverImmersiveStateIfStuck() async {
        await practiceViewModel.recoverImmersiveStateIfStuck()
    }

    func suspendPracticeAndFlushProgress() async {
        invalidatePracticeFeedbackPresentation()
        await practiceSessionViewModel.suspendAndFlushProgress()
    }

    func invalidatePracticeFeedbackPresentation() {
        practiceFeedbackViewModel.cancel()
        practiceSessionViewModel.invalidateFeedbackPresentation()
    }

    func resumePracticeAfterSuspension() {
        practiceSessionViewModel.resumeAfterSuspension()
    }

    func leavePracticeStep() async {
        await practiceSessionViewModel.flushAndShutdown()
        recordingViewModel.stop()
        takePlaybackViewModel.stop()
        setPracticeAutoplayEnabled(false)
        hideVirtualPiano()
        setPracticeVirtualPerformerEnabled(false)
        resetPracticeLocalizationState()
    }

    var recordingElapsedText: String {
        recordingViewModel.recordingElapsedText
    }

    var canRecord: Bool {
        isVirtualPianoEnabled == false
    }

    var recordingSourceText: String? {
        selectedPianoMode?.recordingSourceText()
    }

    var isRecording: Bool {
        recordingViewModel.isRecording
    }

    var takeLibraryTakes: [RecordingTake] {
        recordingViewModel.takes
    }

    var takeLibraryErrorMessage: String? {
        recordingViewModel.errorMessage
    }

    func startRecording() {
        recordingViewModel.startRecording(canRecord: canRecord)
    }

    func stopRecording() {
        recordingViewModel.stopRecording()
    }

    func dismissTakeLibraryError() {
        recordingViewModel.dismissError()
    }

    func renameTake(id: UUID, name: String) {
        recordingViewModel.renameTake(id: id, name: name)
    }

    func deleteTake(id: UUID) {
        recordingViewModel.deleteTake(id: id)
    }

    func clearAllTakes() {
        recordingViewModel.clearAllTakes()
    }

    func makeMIDIExport(for take: RecordingTake) throws -> RecordingMIDIExport {
        try recordingViewModel.makeMIDIExport(for: take)
    }

    func onImmersiveAppear() {
        isImmersiveRuntimeSuspended = false
        switch appState.immersiveMode {
        case .calibration:
            startTrackingIfNeeded()
            calibrationGuideViewModel.onImmersiveAppear()
        case .practice:
            startTrackingIfNeeded()
        }
        if isVirtualPerformerEnabled {
            setPracticeVirtualPerformerEnabled(true)
        }
    }

    func onImmersiveDisappear() {
        isImmersiveRuntimeSuspended = false
        shouldResumeVirtualPerformer = false
        calibrationGuideViewModel.shutdown()
        practiceLocalizationViewModel.shutdown()
        practiceSessionViewModel.stopVirtualPianoInput()
        recordingViewModel.stop()
        aiPerformanceViewModel.shutdown()
        stopTracking()
    }

    func suspendImmersiveRuntime() {
        guard isImmersiveRuntimeSuspended == false else { return }
        isImmersiveRuntimeSuspended = true
        shouldResumeVirtualPerformer = isVirtualPerformerEnabled
        calibrationGuideViewModel.shutdown()
        practiceLocalizationViewModel.shutdown()
        practiceSessionViewModel.stopVirtualPianoInput()
        recordingViewModel.stop()
        aiPerformanceViewModel.shutdown()
        stopTracking()
    }

    func resumeImmersiveRuntimeIfNeeded() {
        guard isImmersiveRuntimeSuspended else { return }
        isImmersiveRuntimeSuspended = false
        startTrackingIfNeeded()
        if appState.immersiveMode == .calibration {
            calibrationGuideViewModel.onImmersiveAppear()
        }
        if shouldResumeVirtualPerformer {
            setPracticeVirtualPerformerEnabled(true)
        }
        shouldResumeVirtualPerformer = false
    }

    func startTrackingIfNeeded() {
        guard isImmersiveRuntimeSuspended == false else { return }

        let desiredRequirements = trackingRequirementsForCurrentContext()
        if desiredRequirements != currentTrackingRequirements {
            cancelHandTrackingConsumer()
            currentTrackingRequirements = desiredRequirements
        }

        arTrackingService.start(requirements: desiredRequirements)

        guard desiredRequirements.contains(.hand) else {
            cancelHandTrackingConsumer()
            stopVirtualPianoGuidance()
            return
        }
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
        stopTracking()
    }

    private func stopTracking() {
        cancelHandTrackingConsumer()
        currentTrackingRequirements = []
        stopVirtualPianoGuidance()
        calibrationGuideViewModel.stopHandTracking()
        arTrackingService.stop()
    }

    private func cancelHandTrackingConsumer() {
        handTrackingConsumerTask?.cancel()
        handTrackingConsumerTask = nil
    }

    private func trackingRequirementsForCurrentContext() -> ARTrackingRequirements {
        switch appState.immersiveMode {
        case .calibration:
            .calibration
        case .practice:
            .practice(
                base: selectedPianoMode?.practiceTrackingRequirements ?? [.hand, .world],
                requiresHorizontalPlanePlacement: isVirtualPianoEnabled
                    && practiceSessionViewModel.keyboardGeometry == nil
            )
        }
    }

    private func handleHandTrackingUpdate(_ fingerTips: FingerTipsSnapshot) {
        switch appState.immersiveMode {
        case .calibration:
            calibrationGuideViewModel.handleHandUpdates()

        case .practice:
            let nowUptime = ProcessInfo.processInfo.systemUptime
            placementViewModel.updateLatestFingerSnapshot(fingerTips)

            if isVirtualPianoEnabled {
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
            calibrationGuideViewModel.setCalibrationPhaseForPreview(phase)
        }
    #endif
}
