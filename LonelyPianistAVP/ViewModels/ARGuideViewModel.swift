import ARKit
import Dispatch
import Foundation
import Observation
import os
import simd

@MainActor
@Observable
final class ARGuideViewModel {
    private let practiceInputLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "LonelyPianistAVP",
        category: "PracticeInput-Recording"
    )
    typealias CalibrationPhase = CalibrationFlowViewModel.CalibrationPhase
    typealias PracticeLocalizationFailure = PracticeLocalizationViewModel.PracticeLocalizationFailure
    typealias PracticeLocalizationState = PracticeLocalizationViewModel.PracticeLocalizationState

    // MARK: - Dependencies
    private let appState: AppState
    let flowState: FlowState
    private let calibrationFlowViewModel: CalibrationFlowViewModel
    private let practiceLocalizationViewModel: PracticeLocalizationViewModel

    // MARK: - Practice Session (P3: split target)
    private let practiceSessionViewModelFactory: PracticeSessionViewModelFactoryProtocol
    private(set) var practiceSessionViewModel: PracticeSessionViewModel
    private var latestPreparedPractice: PreparedPractice?

    // MARK: - Tracking & Long-Lived Tasks (P3: split target)
    private var handTrackingConsumerTask: Task<Void, Never>?
    private var currentTrackingMode: ARTrackingMode?
    private var virtualPianoGuidanceUpdateTask: Task<Void, Never>?

    // MARK: - UI/Flow State (P3: split target)
    private(set) var isVirtualPianoEnabled = false
    private(set) var isVirtualPianoPlaced = false
    private(set) var isVirtualPerformerEnabled = false
    private(set) var isAIPerformanceActive = false
    private(set) var latestAIPerformanceSchedule: [PracticeSequencerMIDIEvent] = []
    private(set) var lastImprovStatusText: String?
    private(set) var latestDeviceWorldPosition: SIMD3<Float>?

    // MARK: - Gaze & Placement (P3: split target)
    let gazePlaneDiskConfirmation = GazePlaneDiskConfirmationViewModel()
    private let gazePlaneHitTestService = GazePlaneHitTestService()
    private var latestGazePlaneHit: PlaneHit?
    private var latestGazeRayOriginWorld: SIMD3<Float>?

    // MARK: - Backend / Improv (P3: split target)
    private let backendDiscoveryService = BonjourBackendDiscoveryService()

    // MARK: - Recording (P3: split target)
    private let takeLibraryViewModel = TakeLibraryViewModel()
    @ObservationIgnored
    private lazy var midiRecordingCoordinator: MIDIRecordingCoordinator = MIDIRecordingCoordinator(
        logger: practiceInputLogger,
        onStateChanged: { [weak self] state in
            guard let self else { return }
            self.isRecording = state.isRecording
            self.recordingStartDate = state.recordingStartDate
        },
        onTakeRecorded: { [weak self] take in
            self?.takeLibraryViewModel.addTake(take)
        },
        onMIDI1Event: { [weak self] event in
            self?.aiPerformanceCoordinator.recordMIDI1EventForPhraseRecordingIfNeeded(event)
        },
        onMIDI2Event: { [weak self] event in
            self?.aiPerformanceCoordinator.recordMIDI2EventForPhraseRecordingIfNeeded(event)
        }
    )
    @ObservationIgnored
    private lazy var aiPerformanceCoordinator: AIPerformanceCoordinator = AIPerformanceCoordinator(
        logger: Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "LonelyPianistAVP",
            category: "AIPerformanceCoordinator"
        ),
        backendDiscoveryService: backendDiscoveryService,
        onStateChanged: { [weak self] state in
            guard let self else { return }
            self.isAIPerformanceActive = state.isAIPerformanceActive
            self.latestAIPerformanceSchedule = state.latestSchedule
            self.lastImprovStatusText = state.lastImprovStatusText
        }
    )
    private let takePlaybackController = TakePlaybackController(
        playbackService: AVAudioSequencerPracticePlaybackService(soundFontResourceName: "SalC5Light2")
    )
    let takePlaybackViewModel: TakePlaybackViewModel
    private(set) var isRecording = false
    private var recordingStartDate: Date?
    private let pianoModeRegistry: PianoModeRegistryProtocol

    init(
        appState: AppState,
        flowState: FlowState,
        pianoModeRegistry: PianoModeRegistryProtocol,
        practiceSessionViewModelFactory: PracticeSessionViewModelFactoryProtocol
    ) {
        self.appState = appState
        self.flowState = flowState
        calibrationFlowViewModel = CalibrationFlowViewModel(appState: appState)
        practiceLocalizationViewModel = PracticeLocalizationViewModel(appState: appState)
        self.pianoModeRegistry = pianoModeRegistry
        self.practiceSessionViewModelFactory = practiceSessionViewModelFactory
        takePlaybackViewModel = TakePlaybackViewModel(controller: takePlaybackController)
        practiceSessionViewModel = practiceSessionViewModelFactory
            .makePracticeSessionViewModel(for: flowState.selectedPianoModeID)
        setupAppStateCallbacks()
    }

    private var selectedPianoMode: (any PianoModeProtocol)? {
        pianoModeRegistry.mode(for: flowState.selectedPianoModeID)
    }

    var isVirtualPianoMode: Bool {
        selectedPianoMode?.isVirtualPianoMode == true
    }

    private func setupAppStateCallbacks() {
        flowState.onStepsImported = { [weak self] prepared in
            guard let self else { return }
            latestPreparedPractice = prepared
            practiceSessionViewModel.setSteps(
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

    private func replacePracticeSessionViewModel() {
        let next = practiceSessionViewModelFactory.makePracticeSessionViewModel(for: flowState.selectedPianoModeID)

        practiceSessionViewModel.shutdown()
        practiceSessionViewModel = next
        aiPerformanceCoordinator.updatePracticeSession(next)

        if let prepared = latestPreparedPractice {
            practiceSessionViewModel.setSteps(
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

        appState.applySessionIfPossible()
        if isVirtualPerformerEnabled {
            setPracticeVirtualPerformerEnabled(true)
        }

        midiRecordingCoordinator.refreshMIDISubscriptionIfNeeded(
            usesBluetoothMIDIInput: selectedPianoMode?.usesBluetoothMIDIInput == true,
            eventSource: practiceSessionViewModel.practiceInputEventSource
        )
    }

    var calibration: PianoCalibration? {
        appState.calibration
    }

    var storedCalibration: StoredWorldAnchorCalibration? {
        appState.storedCalibration
    }

    var calibrationPhase: CalibrationPhase {
        calibrationFlowViewModel.calibrationPhase
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

    var calibrationCaptureService: CalibrationPointCaptureService {
        appState.calibrationCaptureService
    }

    var arTrackingService: ARTrackingServiceProtocol {
        appState.arTrackingService
    }

    var hasImportedSteps: Bool {
        flowState.importedSteps.isEmpty == false
    }

    var immersiveMode: AppState.ImmersiveMode {
        appState.immersiveMode
    }

    var immersiveSpaceState: AppState.ImmersiveSpaceState {
        appState.immersiveSpaceState
    }

    func saveCalibration() {
        _ = appState.saveCalibrationIfPossible()
    }

    func beginCalibrationRecapture() {
        appState.beginCalibrationRecapture()
    }

    func beginCalibrationGuidedFlow() {
        calibrationFlowViewModel.beginCalibrationGuidedFlow()
    }

    func presentCalibrationError(message: String) {
        calibrationFlowViewModel.presentCalibrationError(message: message)
    }

    func endCalibrationGuidedFlow() {
        calibrationFlowViewModel.endCalibrationGuidedFlow()
    }

    @discardableResult
    func showCalibrationCompletedIfStoredCalibrationExists() -> Bool {
        calibrationFlowViewModel.showCalibrationCompletedIfStoredCalibrationExists()
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

    func setPracticeVirtualPianoEnabled(_ isEnabled: Bool) {
        isVirtualPianoEnabled = isEnabled
        if isEnabled {
            practiceSessionViewModel.stopVirtualPianoInput()
            practiceSessionViewModel.clearCalibration()
            practiceLocalizationViewModel.shutdown()
            gazePlaneDiskConfirmation.reset()
            latestGazePlaneHit = nil
            startVirtualPianoGuidanceIfNeeded()
            #if DEBUG && targetEnvironment(simulator)
                practiceLocalizationViewModel.setPracticeLocalizationState(.ready)
                if appState.cachedVirtualPianoWorldAnchorID == nil {
                    applyVirtualPianoGeometryAtDefaultPositionForSimulator()
                }
            #else
                if appState.cachedVirtualPianoWorldAnchorID == nil {
                    practiceLocalizationViewModel.setPracticeLocalizationState(.idle)
                }
            #endif
        } else {
            practiceSessionViewModel.stopVirtualPianoInput()
            practiceSessionViewModel.clearCalibration()
            practiceLocalizationViewModel.setPracticeLocalizationState(.idle)
            gazePlaneDiskConfirmation.reset()
            latestGazePlaneHit = nil
            stopVirtualPianoGuidance()
        }
    }

    func setPracticeVirtualPerformerEnabled(_ isEnabled: Bool) {
        isVirtualPerformerEnabled = isEnabled
        aiPerformanceCoordinator.updatePracticeSession(practiceSessionViewModel)
        aiPerformanceCoordinator.setEnabled(isEnabled)
    }

    var backendStatusText: String? {
        switch backendDiscoveryService.state {
            case .idle:
                "Backend: idle"
            case .discovering:
                "Backend: discovering"
            case let .resolved(host, port):
                "Backend: resolved \(host):\(port)"
            case let .failed(message):
                "Backend: unavailable (\(message))"
            case .denied:
                "Backend: denied (Local Network)"
        }
    }

    var gazePlaneDiskStatusText: String? {
        guard isVirtualPianoEnabled else { return nil }
        if practiceSessionViewModel.keyboardGeometry != nil {
            return nil
        }

        let planeState = arTrackingService.providerStateByName["plane"] ?? .idle
        switch planeState {
            case .unsupported:
                return "虚拟钢琴不可用：此设备/环境不支持平面检测。"
            case .unauthorized:
                return "虚拟钢琴不可用：请在系统设置中允许本 App 使用“周围环境/世界感知”（worldSensing）。"
            case let .failed(reason):
                return "虚拟钢琴不可用：平面检测启动失败（\(reason)）。"
            default:
                break
        }

        let handState = arTrackingService.providerStateByName["hand"] ?? .idle
        switch handState {
            case .unsupported:
                return "虚拟钢琴不可用：此设备不支持手部追踪。"
            case .unauthorized:
                return "虚拟钢琴：已检测到平面，但需要 Hand Tracking 才能确认放好双手。"
            case let .failed(reason):
                return "虚拟钢琴不可用：手部追踪启动失败（\(reason)）。"
            default:
                break
        }

        return gazePlaneDiskConfirmation.statusText
    }

    var isGazePlaneDiskVisible: Bool {
        isVirtualPianoEnabled &&
            practiceSessionViewModel.keyboardGeometry == nil &&
            gazePlaneDiskConfirmation.isDiskVisible
    }

    var gazePlaneDiskWorldTransform: simd_float4x4? {
        guard isGazePlaneDiskVisible else { return nil }
        return gazePlaneDiskConfirmation.diskWorldTransform
    }

    var gazePlaneDiskOverlayText: String? {
        guard isGazePlaneDiskVisible else { return nil }
        return gazePlaneDiskConfirmation.statusText
    }

    var gazePlaneDiskCameraWorldPosition: SIMD3<Float>? {
        guard isGazePlaneDiskVisible else { return nil }
        return latestGazeRayOriginWorld
    }

    var practiceLocalizationState: PracticeLocalizationState {
        practiceLocalizationViewModel.practiceLocalizationState
    }

    var practiceLocalizationStatusText: String? {
        switch practiceLocalizationState {
            case .idle:
                nil
            case let .blocked(reason), let .failed(reason):
                reason.message
            case .openingImmersive:
                "正在打开沉浸空间…"
            case .waitingForProviders:
                "正在启动追踪服务…"
            case let .locating(elapsedSeconds, totalSeconds):
                "正在定位钢琴…（\(elapsedSeconds)/\(totalSeconds)s）"
            case .ready:
                "定位成功，已开始引导。"
        }
    }

    func retryVirtualPianoPlacement() {
        guard isVirtualPianoEnabled else { return }

        practiceSessionViewModel.stopVirtualPianoInput()
        practiceSessionViewModel.clearCalibration()
        if let anchorID = appState.cachedVirtualPianoWorldAnchorID {
            appState.cachedVirtualPianoWorldAnchorID = nil
            Task { @MainActor [weak self] in
                guard let self else { return }
                try? await arTrackingService.worldTrackingProvider.removeAnchor(forID: anchorID)
            }
        }

        gazePlaneDiskConfirmation.reset()
        latestGazePlaneHit = nil

        #if DEBUG && targetEnvironment(simulator)
            applyVirtualPianoGeometryAtDefaultPositionForSimulator()
        #endif
    }

    var canRetryPracticeLocalization: Bool {
        if case .failed = practiceLocalizationState {
            return true
        }
        return false
    }

    var shouldSuggestCalibrationStep: Bool {
        let reason: PracticeLocalizationFailure
        switch practiceLocalizationState {
            case let .blocked(blockingReason), let .failed(blockingReason):
                reason = blockingReason
            default:
                return false
        }

        switch reason {
            case .missingStoredCalibration, .anchorMissing, .anchorNotTracked, .anchorsTooClose:
                return true
            default:
                return false
        }
    }

    var step3ARStatusText: String {
        let worldState = arTrackingService.providerStateByName["world"] ?? .idle
        switch worldState {
            case .running:
                return "AR 定位：可用"
            case .unsupported:
                return "AR 定位：不可用（设备/环境不支持）"
            case let .failed(reason):
                return "AR 定位：失败（\(reason)）"
            default:
                return "AR 定位：初始化中"
        }
    }

    var step3HandAssistStatusText: String {
        let handState = arTrackingService.providerStateByName["hand"] ?? .idle
        switch handState {
            case .running:
                return "手势辅助：可用（boost + fallback）"
            case .disabled:
                return "手势辅助：已关闭（Bluetooth MIDI 模式）"
            case .unauthorized:
                return "手势辅助：不可用（未授权）"
            case let .failed(reason):
                return "手势辅助：不可用（\(reason)）"
            default:
                return "手势辅助：初始化中"
        }
    }

    var step3AudioStatusText: String {
        switch practiceSessionViewModel.audioRecognitionStatus {
            case .idle:
                "音频识别：空闲"
            case .requestingPermission:
                "音频识别：请求麦克风权限"
            case .permissionDenied:
                "音频识别：权限被拒绝"
            case .running:
                "音频识别：运行中"
            case let .engineFailed(reason):
                "音频识别：引擎失败（\(reason)）"
            case .stopped:
                "音频识别：已停止"
        }
    }

    func practiceEntryBlockingReason() -> PracticeLocalizationFailure? {
        if hasImportedSteps == false {
            return .missingImportedSteps
        }

        if isVirtualPianoEnabled == false, storedCalibration == nil {
            return .missingStoredCalibration
        }

        return nil
    }

    func enterPracticeStep(
        openImmersiveSpace: PracticeFlowOpenImmersiveSpaceHandler,
        dismissImmersiveSpace: @escaping PracticeFlowDismissImmersiveSpaceHandler
    ) async {
        replacePracticeSessionViewModel()
        await practiceLocalizationViewModel.beginPracticeLocalization(
            isVirtualPianoEnabled: isVirtualPianoEnabled,
            blockingReason: practiceEntryBlockingReason(),
            openImmersiveSpace: openImmersiveSpace,
            dismissImmersiveSpace: dismissImmersiveSpace,
            openImmersiveForStep: { [weak self] open in
                guard let self else { return "已退出练习流程。" }
                return await self.openImmersiveForStep(mode: .practice, openImmersiveSpace: open)
            },
            closeImmersiveForStep: { [weak self] dismiss in
                guard let self else { return }
                await self.closeImmersiveForStep(dismissImmersiveSpace: dismiss)
            },
            recoverImmersiveStateIfStuck: { [weak self] in
                guard let self else { return }
                await self.recoverImmersiveStateIfStuck()
            }
        )
    }

    func retryPracticeLocalization(
        openImmersiveSpace: PracticeFlowOpenImmersiveSpaceHandler,
        dismissImmersiveSpace: @escaping PracticeFlowDismissImmersiveSpaceHandler
    ) async {
        replacePracticeSessionViewModel()
        await practiceLocalizationViewModel.beginPracticeLocalization(
            isVirtualPianoEnabled: isVirtualPianoEnabled,
            blockingReason: practiceEntryBlockingReason(),
            openImmersiveSpace: openImmersiveSpace,
            dismissImmersiveSpace: dismissImmersiveSpace,
            openImmersiveForStep: { [weak self] open in
                guard let self else { return "已退出练习流程。" }
                return await self.openImmersiveForStep(mode: .practice, openImmersiveSpace: open)
            },
            closeImmersiveForStep: { [weak self] dismiss in
                guard let self else { return }
                await self.closeImmersiveForStep(dismissImmersiveSpace: dismiss)
            },
            recoverImmersiveStateIfStuck: { [weak self] in
                guard let self else { return }
                await self.recoverImmersiveStateIfStuck()
            }
        )
    }

    func enterVirtualPianoPlacement(
        openImmersiveSpace: PracticeFlowOpenImmersiveSpaceHandler
    ) async {
        guard isVirtualPianoEnabled == false else { return }
        setPracticeVirtualPianoEnabled(true)
        isVirtualPianoPlaced = false

        practiceLocalizationViewModel.setPracticeLocalizationState(.openingImmersive)
        if let openError = await openImmersiveForStep(mode: .practice, openImmersiveSpace: openImmersiveSpace) {
            practiceLocalizationViewModel.setPracticeLocalizationState(.failed(reason: .immersiveOpenFailed(message: openError)))
            return
        }

        practiceLocalizationViewModel.setPracticeLocalizationState(.ready)
    }

    func resetPracticeLocalizationState() {
        practiceLocalizationViewModel.resetPracticeLocalizationState()
    }

    func practiceLocalizationTimeoutFailure(
        lastRecoverableResolution: AppState.PracticeCalibrationResolutionResult?
    ) -> PracticeLocalizationFailure {
        practiceLocalizationViewModel.practiceLocalizationTimeoutFailure(
            lastRecoverableResolution: lastRecoverableResolution
        )
    }

    func openImmersiveForStep(
        mode: AppState.ImmersiveMode,
        openImmersiveSpace: PracticeFlowOpenImmersiveSpaceHandler
    ) async -> String? {
        appState.immersiveMode = mode

        switch appState.immersiveSpaceState {
            case .open:
                return nil

            case .inTransition:
                for _ in 0 ..< 40 {
                    await Task.yield()
                    if appState.immersiveSpaceState != .inTransition {
                        break
                    }
                }

                if appState.immersiveSpaceState == .closed {
                    return await openImmersiveForStep(mode: mode, openImmersiveSpace: openImmersiveSpace)
                }
                return nil

            case .closed:
                appState.immersiveSpaceState = .inTransition
                switch await openImmersiveSpace(appState.immersiveSpaceID) {
                    case .opened:
                        // Don't set immersiveSpaceState to .open here.
                        // ImmersiveView.onAppear is the single source of truth.
                        return nil

                    case .userCancelled:
                        appState.immersiveSpaceState = .closed
                        return "已取消打开沉浸空间。"

                    case .error:
                        appState.immersiveSpaceState = .closed
                        return "打开沉浸空间失败，请重试。"

                    case .unknown:
                        appState.immersiveSpaceState = .closed
                        return "沉浸空间返回未知状态，请重试。"
                }
        }
    }

    func closeImmersiveForStep(dismissImmersiveSpace: PracticeFlowDismissImmersiveSpaceHandler) async {
        guard appState.immersiveSpaceState != .closed else { return }
        if appState.immersiveSpaceState == .open {
            appState.immersiveSpaceState = .inTransition
        }
        await dismissImmersiveSpace()
        // Don't set immersiveSpaceState to .closed here.
        // ImmersiveView.onDisappear is the single source of truth.
    }

    func recoverImmersiveStateIfStuck() async {
        guard appState.immersiveSpaceState == .inTransition else { return }
        for _ in 0 ..< 40 {
            await Task.yield()
            if appState.immersiveSpaceState != .inTransition {
                return
            }
        }
        appState.immersiveSpaceState = .closed
    }

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
        midiRecordingCoordinator.stop()
        stopHandTracking()
    }

    func startTrackingIfNeeded() {
        let desiredMode: ARTrackingMode = switch appState.immersiveMode {
            case .calibration:
                .calibration
            case .practice:
                selectedPianoMode?
                    .practiceTrackingMode(isVirtualPianoEnabled: isVirtualPianoEnabled) ?? .practiceVirtualOrAudio
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
                switch appState.immersiveMode {
                    case .calibration:
                        calibrationFlowViewModel.handleHandUpdates()
                    case .practice:
                        let nowUptime = ProcessInfo.processInfo.systemUptime
                        updateLatestDeviceWorldPosition(nowUptime: nowUptime)
                        if isAIPerformanceActive {
                            continue
                        }
                        if isVirtualPianoEnabled {
                            updateGazePlaneDiskGuidance(fingerTips: fingerTips, nowUptime: nowUptime)
                            if practiceSessionViewModel.keyboardGeometry != nil {
                                _ = practiceSessionViewModel.handleFingerTipPositions(
                                    fingerTips,
                                    isVirtualPiano: true
                                )
                                recordPhraseIfNeeded(nowUptime: nowUptime)
                            }
                        } else {
                            _ = practiceSessionViewModel.handleFingerTipPositions(fingerTips)
                            recordPhraseIfNeeded(nowUptime: nowUptime)
                            recordTakeIfNeeded(nowUptime: nowUptime)
                        }
                }
            }
        }
    }

    private func recordPhraseIfNeeded(nowUptime: TimeInterval) {
        aiPerformanceCoordinator.recordKeyContactForPhraseRecordingIfNeeded(
            usesBluetoothMIDIInput: selectedPianoMode?.usesBluetoothMIDIInput == true,
            keyContact: practiceSessionViewModel.latestKeyContactResult,
            nowUptimeSeconds: nowUptime
        )
    }

    private func recordTakeIfNeeded(nowUptime: TimeInterval) {
        midiRecordingCoordinator.recordTakeFromKeyContactIfNeeded(
            usesBluetoothMIDIInput: selectedPianoMode?.usesBluetoothMIDIInput == true,
            isVirtualPianoEnabled: isVirtualPianoEnabled,
            keyContact: practiceSessionViewModel.latestKeyContactResult,
            nowUptimeSeconds: nowUptime
        )
    }

    private func updateLatestDeviceWorldPosition(nowUptime: TimeInterval) {
        guard
            let deviceAnchor = arTrackingService.worldTrackingProvider.queryDeviceAnchor(atTimestamp: nowUptime),
            deviceAnchor.isTracked
        else { return }
        let deviceWorldTransform = deviceAnchor.originFromAnchorTransform
        latestDeviceWorldPosition = SIMD3<Float>(
            deviceWorldTransform.columns.3.x,
            deviceWorldTransform.columns.3.y,
            deviceWorldTransform.columns.3.z
        )
    }

    private func applyVirtualPianoGeometry(worldFromKeyboard: simd_float4x4) {
        let frame = KeyboardFrame(worldFromKeyboard: worldFromKeyboard)
        let service = VirtualPianoKeyGeometryService()
        if let geometry = service.generateKeyboardGeometry(from: frame) {
            practiceSessionViewModel.applyVirtualKeyboardGeometry(geometry)
            isVirtualPianoPlaced = true
            if appState.cachedVirtualPianoWorldAnchorID == nil {
                let anchor = WorldAnchor(originFromAnchorTransform: worldFromKeyboard)
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    do {
                        try await arTrackingService.worldTrackingProvider.addAnchor(anchor)
                        appState.cachedVirtualPianoWorldAnchorID = anchor.id
                    } catch {
                        // If we can't persist the anchor, the user can still play in this session.
                    }
                }
            }
        }
    }

    #if DEBUG && targetEnvironment(simulator)
        private func applyVirtualPianoGeometryAtDefaultPositionForSimulator() {
            let xAxisWorld = SIMD3<Float>(1, 0, 0)
            let yAxisWorld = SIMD3<Float>(0, 1, 0)
            let zAxis = simd_normalize(simd_cross(xAxisWorld, yAxisWorld))
            let xAxis = simd_normalize(simd_cross(yAxisWorld, zAxis))

            let centerPoint = SIMD3<Float>(0, 1.0, -1.0)
            let originWorld = centerPoint - xAxis * (VirtualPianoKeyGeometryService.totalKeyboardLengthMeters / 2)

            let worldFromKeyboard = simd_float4x4(columns: (
                SIMD4<Float>(xAxis, 0),
                SIMD4<Float>(yAxisWorld, 0),
                SIMD4<Float>(zAxis, 0),
                SIMD4<Float>(originWorld, 1)
            ))

            applyVirtualPianoGeometry(worldFromKeyboard: worldFromKeyboard)
        }
    #endif

    func stopHandTracking() {
        handTrackingConsumerTask?.cancel()
        handTrackingConsumerTask = nil
        currentTrackingMode = nil
        stopVirtualPianoGuidance()
        calibrationFlowViewModel.stopHandTracking()
        arTrackingService.stop()
    }

    private func startVirtualPianoGuidanceIfNeeded() {
        guard appState.immersiveMode == .practice else { return }
        guard isVirtualPianoEnabled else { return }
        guard practiceSessionViewModel.keyboardGeometry == nil else { return }
        guard appState.immersiveSpaceState == .open else { return }
        guard virtualPianoGuidanceUpdateTask == nil else { return }

        virtualPianoGuidanceUpdateTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while Task.isCancelled == false {
                let nowUptime = ProcessInfo.processInfo.systemUptime
                updateGazePlaneDiskGuidance(fingerTips: arTrackingService.fingerTipPositions, nowUptime: nowUptime)
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    private func stopVirtualPianoGuidance() {
        virtualPianoGuidanceUpdateTask?.cancel()
        virtualPianoGuidanceUpdateTask = nil
    }

    private func updateGazePlaneDiskGuidance(
        fingerTips: [String: SIMD3<Float>],
        nowUptime: TimeInterval
    ) {
        guard isVirtualPianoEnabled else { return }

        if
            practiceSessionViewModel.keyboardGeometry == nil,
            let anchorID = appState.cachedVirtualPianoWorldAnchorID,
            let anchor = arTrackingService.worldAnchorsByID[anchorID],
            anchor.isTracked
        {
            applyVirtualPianoGeometry(worldFromKeyboard: anchor.originFromAnchorTransform)
            return
        }

        let deviceWorldTransform: simd_float4x4? = if
            let deviceAnchor = arTrackingService.worldTrackingProvider.queryDeviceAnchor(atTimestamp: nowUptime),
            deviceAnchor.isTracked
        {
            deviceAnchor.originFromAnchorTransform
        } else {
            nil
        }

        let ray: GazeRay? = {
            guard let deviceWorldTransform else { return nil }
            let origin = SIMD3<Float>(
                deviceWorldTransform.columns.3.x,
                deviceWorldTransform.columns.3.y,
                deviceWorldTransform.columns.3.z
            )
            let forward = -SIMD3<Float>(
                deviceWorldTransform.columns.2.x,
                deviceWorldTransform.columns.2.y,
                deviceWorldTransform.columns.2.z
            )
            return GazeRay(originWorld: origin, directionWorld: forward)
        }()
        latestGazeRayOriginWorld = ray?.originWorld

        let planes: [DetectedPlane] = arTrackingService.planeAnchorsByID.values.map { anchor in
            DetectedPlane(id: anchor.id, worldFromPlane: anchor.originFromAnchorTransform)
        }

        let hit = ray.flatMap { gazePlaneHitTestService.hitTest(ray: $0, planes: planes) }
        latestGazePlaneHit = hit

        gazePlaneDiskConfirmation.update(
            planeHit: hit,
            leftPalmWorld: fingerTips["left-palmCenter"],
            rightPalmWorld: fingerTips["right-palmCenter"],
            nowUptime: nowUptime
        )

        guard gazePlaneDiskConfirmation.isConfirmed else { return }
        guard practiceSessionViewModel.keyboardGeometry == nil else { return }
        guard let hit else { return }
        guard let planeWorldFromAnchor = arTrackingService.planeAnchorsByID[hit.id]?.originFromAnchorTransform
        else { return }
        guard let leftPalm = fingerTips["left-palmCenter"],
              let rightPalm = fingerTips["right-palmCenter"] else { return }

        let handCenterWorld = (leftPalm + rightPalm) / 2
        let n = simd_normalize(hit.planeNormalWorld)
        let handCenterOnPlaneWorld = handCenterWorld - n * simd_dot(handCenterWorld - hit.hitPointWorld, n)

        let poseService = VirtualKeyboardPoseService()
        guard let worldFromKeyboard = poseService.computeWorldFromKeyboard(
            planeWorldFromAnchor: planeWorldFromAnchor,
            handCenterOnPlaneWorld: handCenterOnPlaneWorld,
            deviceWorldTransform: deviceWorldTransform
        ) else { return }

        applyVirtualPianoGeometry(worldFromKeyboard: worldFromKeyboard)
    }

    var practiceProgressText: String {
        guard flowState.importedSteps.isEmpty == false else { return "0 / 0" }
        let total = flowState.importedSteps.count
        switch practiceSessionViewModel.state {
            case .idle, .ready:
                return "0 / \(total)"
            case let .guiding(index):
                return "\(min(index + 1, total)) / \(total)"
            case .completed:
                return "\(total) / \(total)"
        }
    }

    var recordingElapsedText: String {
        guard let startDate = recordingStartDate else { return "00:00" }
        let elapsed = Date().timeIntervalSince(startDate)
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60
        let minutesText = minutes.formatted(.number.precision(.integerLength(2)))
        let secondsText = seconds.formatted(.number.precision(.integerLength(2)))
        return "\(minutesText):\(secondsText)"
    }

    var canRecord: Bool {
        isVirtualPianoEnabled == false
    }

    var recordingSourceText: String? {
        selectedPianoMode?.recordingSourceText()
    }

    func startRecording() {
        guard canRecord else { return }
        takePlaybackViewModel.stop()
        midiRecordingCoordinator.startRecordingIfPossible(canRecord: canRecord)
    }

    func stopRecording() {
        midiRecordingCoordinator.stopRecordingIfNeeded()
    }

    var takeLibraryTakes: [RecordingTake] {
        takeLibraryViewModel.takes
    }

    var takeLibraryErrorMessage: String? {
        takeLibraryViewModel.errorMessage
    }

    func dismissTakeLibraryError() {
        takeLibraryViewModel.dismissError()
    }

    func renameTake(id: UUID, name: String) {
        takeLibraryViewModel.rename(takeID: id, to: name)
    }

    func deleteTake(id: UUID) {
        takeLibraryViewModel.delete(takeID: id)
    }

    func clearAllTakes() {
        takeLibraryViewModel.clearAll()
    }

    private func resolvedTrackedWorldAnchorPoint(anchorID: UUID?) -> SIMD3<Float>? {
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
