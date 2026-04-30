import ARKit
import Foundation
import Observation
import simd
import SwiftUI

@MainActor
@Observable
final class ARGuideViewModel {
    enum CalibrationPhase: Equatable {
        case capturingA0
        case transitionA0
        case capturingC8
        case transitionC8
        case completed
        case error(message: String)
    }

    enum PracticeLocalizationFailure: Equatable {
        case missingImportedSteps
        case missingStoredCalibration
        case handTrackingDenied
        case worldTrackingUnsupported
        case providerNotRunning(state: String)
        case anchorMissing(id: UUID)
        case anchorNotTracked(id: UUID, waitedSeconds: Int)
        case anchorsTooClose(distanceMeters: Float)
        case devicePoseUnavailable(waitedSeconds: Int)
        case immersiveOpenFailed(message: String)

        var message: String {
            switch self {
                case .missingImportedSteps:
                    "请先导入 MusicXML。"
                case .missingStoredCalibration:
                    "未发现校准数据，请先 Step 1 校准。"
                case .handTrackingDenied:
                    "无法定位：Hand Tracking 权限未授权（请在系统设置中允许本 App 访问）。"
                case .worldTrackingUnsupported:
                    "无法定位：此环境不支持 World Tracking。"
                case let .providerNotRunning(state):
                    "无法定位：WorldTrackingProvider 未运行（state=\(state)）。"
                case let .anchorMissing(id):
                    "无法定位：未在当前环境恢复已保存的锚点（id=\(id.uuidString)）。"
                case let .anchorNotTracked(id, waitedSeconds):
                    "无法定位：锚点存在但尚未追踪（id=\(id.uuidString)，已等待 \(waitedSeconds) 秒）。"
                case let .anchorsTooClose(distanceMeters):
                    "校准数据异常：A0 与 C8 距离过近（\(String(format: "%.3f", distanceMeters))m）。请返回 Step 1 重新校准。"
                case let .devicePoseUnavailable(waitedSeconds):
                    "无法定位：设备位姿尚不可用（已等待 \(waitedSeconds) 秒）。"
                case let .immersiveOpenFailed(message):
                    message
            }
        }
    }

    enum PracticeLocalizationState: Equatable {
        case idle
        case blocked(reason: PracticeLocalizationFailure)
        case openingImmersive
        case waitingForProviders
        case locating(elapsedSeconds: Int, totalSeconds: Int)
        case failed(reason: PracticeLocalizationFailure)
        case ready
    }

    private let appState: AppState
    let practiceSessionViewModel: PracticeSessionViewModel
    private var handTrackingConsumerTask: Task<Void, Never>?
    private var calibrationAnchorCaptureTask: Task<Void, Never>?
    private var calibrationFlowBootstrapTask: Task<Void, Never>?
    private var calibrationGuidedFlowTask: Task<Void, Never>?
    private var calibrationSupportPollTask: Task<Void, Never>?
    private var practiceLocalizationTask: Task<Void, Never>?
    private var wasRightHandPinching = false
    private var wasLeftHandPinching = false
    private let providerStartupTimeoutSeconds = 5
    private let practiceLocalizationTimeoutSeconds = 5
    private let practiceLocalizationPollingIntervalNanoseconds: UInt64 = 250_000_000

    private(set) var practiceLocalizationState: PracticeLocalizationState = .idle
    private(set) var calibrationPhase: CalibrationPhase = .capturingA0
    private(set) var isVirtualPianoEnabled = false

    init(appState: AppState, practiceSessionViewModel: PracticeSessionViewModel? = nil) {
        self.appState = appState
        self.practiceSessionViewModel = practiceSessionViewModel ?? PracticeSessionViewModel()
        setupAppStateCallbacks()
    }

    private func setupAppStateCallbacks() {
        appState.onStepsImported = { [weak self] prepared in
            guard let self else { return }
            self.practiceSessionViewModel.setSteps(
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
            self.appState.applySessionIfPossible()
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

    var calibration: PianoCalibration? {
        appState.calibration
    }

    var storedCalibration: StoredWorldAnchorCalibration? {
        appState.storedCalibration
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
        appState.importedSteps.isEmpty == false
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
        cancelCalibrationGuidedFlowTasks()
        calibrationPhase = .capturingA0
        calibrationFlowBootstrapTask = Task { @MainActor [weak self] in
            guard let self else { return }
            beginCalibrationRecapture()

            for _ in 0 ..< 40 {
                guard Task.isCancelled == false else { return }
                if calibrationCaptureService.a0AnchorID == nil,
                   calibrationCaptureService.c8AnchorID == nil
                {
                    break
                }
                try? await Task.sleep(for: .milliseconds(50))
            }

            calibrationStatusMessage = nil
            pendingCalibrationCaptureAnchor = .a0
            calibrationPhase = .capturingA0
            calibrationFlowBootstrapTask = nil
        }
    }

    func presentCalibrationError(message: String) {
        cancelCalibrationGuidedFlowTasks()
        calibrationStatusMessage = message
        pendingCalibrationCaptureAnchor = nil
        calibrationPhase = .error(message: message)
    }

    func endCalibrationGuidedFlow() {
        cancelCalibrationGuidedFlowTasks()
    }

    @discardableResult
    func showCalibrationCompletedIfStoredCalibrationExists() -> Bool {
        guard storedCalibration != nil else { return false }
        endCalibrationGuidedFlow()
        calibrationStatusMessage = nil
        pendingCalibrationCaptureAnchor = nil
        calibrationPhase = .completed
        return true
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
            cancelPracticeLocalizationTask()
            practiceLocalizationState = .idle
        }
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
        using openImmersiveSpace: OpenImmersiveSpaceAction,
        dismissImmersiveSpace: DismissImmersiveSpaceAction
    ) async {
        await beginPracticeLocalization(
            using: openImmersiveSpace,
            dismissImmersiveSpace: dismissImmersiveSpace
        )
    }

    func retryPracticeLocalization(
        using openImmersiveSpace: OpenImmersiveSpaceAction,
        dismissImmersiveSpace: DismissImmersiveSpaceAction
    ) async {
        await beginPracticeLocalization(
            using: openImmersiveSpace,
            dismissImmersiveSpace: dismissImmersiveSpace
        )
    }

    func resetPracticeLocalizationState() {
        cancelPracticeLocalizationTask()
        practiceLocalizationState = .idle
    }

    func openImmersiveForStep(
        mode: AppState.ImmersiveMode,
        using openImmersiveSpace: OpenImmersiveSpaceAction
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
                    return await openImmersiveForStep(mode: mode, using: openImmersiveSpace)
                }
                return nil

            case .closed:
                appState.immersiveSpaceState = .inTransition
                switch await openImmersiveSpace(id: appState.immersiveSpaceID) {
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

                    @unknown default:
                        appState.immersiveSpaceState = .closed
                        return "沉浸空间返回未知状态，请重试。"
                }
        }
    }

    func closeImmersiveForStep(using dismissImmersiveSpace: DismissImmersiveSpaceAction) async {
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
                wasRightHandPinching = false
                wasLeftHandPinching = false
                startHandTrackingIfNeeded()
                startCalibrationSupportPollingIfNeeded()
                updateCalibrationTrackingStatusIfNeeded()

            case .practice:
                startHandTrackingIfNeeded()
        }
    }

    func onImmersiveDisappear() {
        cancelCalibrationGuidedFlowTasks()
        cancelPracticeLocalizationTask()
        stopHandTracking()
    }

    func startHandTrackingIfNeeded() {
        guard handTrackingConsumerTask == nil else { return }
        arTrackingService.start()
        let updates = arTrackingService.fingerTipUpdatesStream()
        handTrackingConsumerTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await fingerTips in updates {
                guard Task.isCancelled == false else { return }
                switch appState.immersiveMode {
                    case .calibration:
                        handleCalibrationHandUpdates()
                    case .practice:
                        _ = practiceSessionViewModel.handleFingerTipPositions(fingerTips)
                }
            }
        }
    }

    private func handleCalibrationHandUpdates() {
        let nowUptime = ProcessInfo.processInfo.systemUptime
        let reticleSourcePoint: SIMD3<Float>? = switch pendingCalibrationCaptureAnchor {
            case .c8:
                arTrackingService.rightIndexFingerTipPosition
            case .a0, .none:
                arTrackingService.leftIndexFingerTipPosition
        }
        calibrationCaptureService.updateReticleFromHandTracking(
            reticleSourcePoint,
            nowUptime: nowUptime
        )
        updateCalibrationTrackingStatusIfNeeded()

        let pinchDistanceThresholdMeters: Float = 0.018

        let isLeftHandPinching: Bool = {
            guard
                let leftIndex = arTrackingService.leftIndexFingerTipPosition,
                let leftThumb = arTrackingService.leftThumbTipPosition
            else {
                return false
            }
            return simd_length(leftIndex - leftThumb) < pinchDistanceThresholdMeters
        }()

        let isRightHandPinching: Bool = {
            guard
                let rightIndex = arTrackingService.rightIndexFingerTipPosition,
                let rightThumb = arTrackingService.rightThumbTipPosition
            else {
                return false
            }
            return simd_length(rightIndex - rightThumb) < pinchDistanceThresholdMeters
        }()

        let shouldConfirmOnPinch: Bool = switch pendingCalibrationCaptureAnchor {
            case .a0, .none:
                isRightHandPinching && wasRightHandPinching == false
            case .c8:
                isLeftHandPinching && wasLeftHandPinching == false
        }

        if shouldConfirmOnPinch {
            calibrationAnchorCaptureTask?.cancel()
            calibrationAnchorCaptureTask = Task { @MainActor [weak self] in
                guard let self else { return }
                await confirmPendingCalibrationAnchorIfReady()
                calibrationAnchorCaptureTask = nil
            }
        }
        wasRightHandPinching = isRightHandPinching
        wasLeftHandPinching = isLeftHandPinching
    }

    private func updateCalibrationTrackingStatusIfNeeded() {
        guard appState.immersiveMode == .calibration else { return }
        guard calibrationPhase != .completed else { return }

        let handState = arTrackingService.providerStateByName["hand"] ?? .idle
        let worldState = arTrackingService.providerStateByName["world"] ?? .idle
        let failureMessage: String? = switch (handState, worldState) {
            case (.unsupported, _):
                "手部追踪不可用：此设备不支持手部追踪。"
            case (.unauthorized, _):
                "手部追踪未授权：请在系统设置中允许本 App 使用 Hand Tracking。"
            case let (.failed(reason), _):
                "手部追踪启动失败：\(reason)"
            case (_, .unsupported):
                "世界追踪不可用：此环境不支持 World Tracking。"
            case (_, .unauthorized):
                "世界追踪不可用：WorldTrackingProvider 未能启动（请稍后重试）。"
            case let (_, .failed(reason)):
                "世界追踪启动失败：\(reason)"
            default:
                nil
        }

        guard let failureMessage else { return }
        presentCalibrationError(message: failureMessage)
    }

    private func confirmPendingCalibrationAnchorIfReady() async {
        guard let pendingAnchor = pendingCalibrationCaptureAnchor else { return }
        guard calibrationCaptureService.isReticleReadyToConfirm else {
            let fingerText = pendingAnchor == .a0 ? "左手食指" : "右手食指"
            let keyText = pendingAnchor == .a0 ? "A0" : "C8"
            let pinchHandText = pendingAnchor == .a0 ? "右手" : "左手"
            calibrationStatusMessage = "请先将\(fingerText)放稳在 \(keyText) 键上（等待准星变绿），再用\(pinchHandText)捏合确认。"
            return
        }

        let oldAnchorID = calibrationCaptureService.anchorID(for: pendingAnchor)
        let reticlePoint = calibrationCaptureService.reticlePoint

        var anchorTransform = matrix_identity_float4x4
        anchorTransform.columns.3 = SIMD4<Float>(reticlePoint.x, reticlePoint.y, reticlePoint.z, 1)
        let worldAnchor = WorldAnchor(originFromAnchorTransform: anchorTransform)

        do {
            try await arTrackingService.worldTrackingProvider.addAnchor(worldAnchor)
            calibrationCaptureService.setAnchorID(worldAnchor.id, for: pendingAnchor)
            calibrationStatusMessage = "已锁定 \(pendingAnchor == .a0 ? "A0" : "C8")"
            pendingCalibrationCaptureAnchor = nil
            onCalibrationAnchorConfirmed(pendingAnchor)

            if let oldAnchorID,
               oldAnchorID != worldAnchor.id,
               let oldAnchor = arTrackingService.worldAnchorsByID[oldAnchorID]
            {
                try? await arTrackingService.worldTrackingProvider.removeAnchor(oldAnchor)
            }
        } catch {
            calibrationStatusMessage = "锁定失败：\(error.localizedDescription)"
            presentCalibrationError(message: calibrationStatusMessage ?? "锁定失败")
        }
    }

    func stopHandTracking() {
        calibrationAnchorCaptureTask?.cancel()
        calibrationAnchorCaptureTask = nil
        handTrackingConsumerTask?.cancel()
        handTrackingConsumerTask = nil
        calibrationSupportPollTask?.cancel()
        calibrationSupportPollTask = nil
        arTrackingService.stop()
    }

    var practiceProgressText: String {
        guard appState.importedSteps.isEmpty == false else { return "0 / 0" }
        let total = appState.importedSteps.count
        switch practiceSessionViewModel.state {
            case .idle, .ready:
                return "0 / \(total)"
            case let .guiding(index):
                return "\(min(index + 1, total)) / \(total)"
            case .completed:
                return "\(total) / \(total)"
        }
    }

    private func beginPracticeLocalization(
        using openImmersiveSpace: OpenImmersiveSpaceAction,
        dismissImmersiveSpace: DismissImmersiveSpaceAction
    ) async {
        cancelPracticeLocalizationTask()
        appState.clearRuntimeCalibrationForPracticeRelocation()

        guard let blockingReason = practiceEntryBlockingReason() else {
            practiceLocalizationState = .openingImmersive
            if let openError = await openImmersiveForStep(mode: .practice, using: openImmersiveSpace) {
                practiceLocalizationState = .failed(reason: .immersiveOpenFailed(message: openError))
                return
            }

            if isVirtualPianoEnabled {
                practiceLocalizationState = .ready
                return
            }

            practiceLocalizationTask = Task { @MainActor [weak self] in
                guard let self else { return }
                await runPracticeLocalization(dismissImmersiveSpace: dismissImmersiveSpace)
                practiceLocalizationTask = nil
            }
            return
        }

        practiceLocalizationState = .blocked(reason: blockingReason)
    }

    private func runPracticeLocalization(
        dismissImmersiveSpace: DismissImmersiveSpaceAction
    ) async {
        practiceLocalizationState = .waitingForProviders

        if let startupFailure = await waitForProvidersToRunOrFail() {
            guard Task.isCancelled == false else { return }
            await handlePracticeLocalizationFailure(startupFailure, dismissImmersiveSpace: dismissImmersiveSpace)
            return
        }

        let startedAt = ProcessInfo.processInfo.systemUptime
        var lastRecoverableResolution: AppState.PracticeCalibrationResolutionResult?

        while Task.isCancelled == false {
            if let hardFailure = immediatePracticeFailureReason() {
                await handlePracticeLocalizationFailure(hardFailure, dismissImmersiveSpace: dismissImmersiveSpace)
                return
            }

            let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
            let elapsedSeconds = min(practiceLocalizationTimeoutSeconds, Int(elapsed.rounded(.down)))
            practiceLocalizationState = .locating(
                elapsedSeconds: elapsedSeconds,
                totalSeconds: practiceLocalizationTimeoutSeconds
            )

            switch appState.resolveRuntimeCalibrationFromTrackedAnchors() {
                case .resolved:
                    practiceLocalizationState = .ready
                    return

                case .missingStoredCalibration:
                    await handlePracticeLocalizationFailure(
                        .missingStoredCalibration,
                        dismissImmersiveSpace: dismissImmersiveSpace
                    )
                    return

                case let .anchorMissing(id):
                    lastRecoverableResolution = .anchorMissing(id: id)

                case let .anchorNotTracked(id):
                    lastRecoverableResolution = .anchorNotTracked(id: id)

                case let .anchorsTooClose(distanceMeters):
                    await handlePracticeLocalizationFailure(
                        .anchorsTooClose(distanceMeters: distanceMeters),
                        dismissImmersiveSpace: dismissImmersiveSpace
                    )
                    return

                case .devicePoseUnavailable:
                    lastRecoverableResolution = .devicePoseUnavailable
            }

            if elapsed >= Double(practiceLocalizationTimeoutSeconds) {
                break
            }

            try? await Task.sleep(nanoseconds: practiceLocalizationPollingIntervalNanoseconds)
        }

        guard Task.isCancelled == false else { return }

        let timeoutFailure = practiceLocalizationTimeoutFailure(
            lastRecoverableResolution: lastRecoverableResolution
        )

        await handlePracticeLocalizationFailure(timeoutFailure, dismissImmersiveSpace: dismissImmersiveSpace)
    }

    func practiceLocalizationTimeoutFailure(
        lastRecoverableResolution: AppState.PracticeCalibrationResolutionResult?
    ) -> PracticeLocalizationFailure {
        guard let lastRecoverableResolution else {
            return .providerNotRunning(state: currentProviderStateSummary())
        }

        switch lastRecoverableResolution {
            case let .anchorMissing(id):
                return .anchorMissing(id: id)
            case let .anchorNotTracked(id):
                return .anchorNotTracked(
                    id: id,
                    waitedSeconds: practiceLocalizationTimeoutSeconds
                )
            case let .anchorsTooClose(distanceMeters):
                return .anchorsTooClose(distanceMeters: distanceMeters)
            case .devicePoseUnavailable:
                return .devicePoseUnavailable(waitedSeconds: practiceLocalizationTimeoutSeconds)
            case .resolved:
                return .providerNotRunning(state: currentProviderStateSummary())
            case .missingStoredCalibration:
                return .missingStoredCalibration
        }
    }

    private func waitForProvidersToRunOrFail() async -> PracticeLocalizationFailure? {
        let startedAt = ProcessInfo.processInfo.systemUptime

        while Task.isCancelled == false {
            if let hardFailure = immediatePracticeFailureReason() {
                return hardFailure
            }

            let worldState = arTrackingService.providerStateByName["world"] ?? .idle
            if worldState == .running {
                return nil
            }

            if ProcessInfo.processInfo.systemUptime - startedAt >= Double(providerStartupTimeoutSeconds) {
                return .providerNotRunning(state: currentProviderStateSummary())
            }

            try? await Task.sleep(nanoseconds: practiceLocalizationPollingIntervalNanoseconds)
        }

        return nil
    }

    private func immediatePracticeFailureReason() -> PracticeLocalizationFailure? {
        if arTrackingService.isWorldTrackingSupported == false {
            return .worldTrackingUnsupported
        }

        if let worldState = arTrackingService.providerStateByName["world"] {
            switch worldState {
                case .unsupported:
                    return .worldTrackingUnsupported
                case .unauthorized:
                    return .providerNotRunning(state: currentProviderStateSummary())
                case let .failed(reason):
                    return .providerNotRunning(state: "world=failed(\(reason))")
                default:
                    break
            }
        }

        return nil
    }

    private func currentProviderStateSummary() -> String {
        let worldState = arTrackingService.providerStateByName["world"]?.description ?? "unknown"
        let handState = arTrackingService.providerStateByName["hand"]?.description ?? "unknown"
        return "world=\(worldState), hand=\(handState)"
    }

    private func handlePracticeLocalizationFailure(
        _ failure: PracticeLocalizationFailure,
        dismissImmersiveSpace: DismissImmersiveSpaceAction
    ) async {
        guard Task.isCancelled == false else { return }

        practiceLocalizationState = .failed(reason: failure)
        appState.clearRuntimeCalibrationForPracticeRelocation()

        await closeImmersiveForStep(using: dismissImmersiveSpace)
        await recoverImmersiveStateIfStuck()
    }

    private func cancelPracticeLocalizationTask() {
        practiceLocalizationTask?.cancel()
        practiceLocalizationTask = nil
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

    private func onCalibrationAnchorConfirmed(_ anchor: CalibrationAnchorPoint) {
        guard calibrationPhase != .completed else { return }
        if case .error = calibrationPhase { return }

        calibrationGuidedFlowTask?.cancel()
        calibrationGuidedFlowTask = Task { @MainActor [weak self] in
            guard let self else { return }
            switch anchor {
                case .a0:
                    calibrationPhase = .transitionA0
                    calibrationStatusMessage = nil
                    try? await Task.sleep(for: .seconds(1.25))
                    guard Task.isCancelled == false else { return }
                    pendingCalibrationCaptureAnchor = .c8
                    calibrationPhase = .capturingC8

                case .c8:
                    calibrationPhase = .transitionC8
                    let capturedA0 = calibrationCaptureService.a0AnchorID
                    let capturedC8 = calibrationCaptureService.c8AnchorID
                    calibrationStatusMessage = nil
                    try? await Task.sleep(for: .seconds(0.3))
                    guard Task.isCancelled == false else { return }

                    let didSave = appState.saveCalibrationIfPossible()
                    if didSave,
                       let storedCalibration,
                       storedCalibration.a0AnchorID == capturedA0,
                       storedCalibration.c8AnchorID == capturedC8
                    {
                        calibrationStatusMessage = nil
                        calibrationPhase = .completed
                    } else {
                        let message = calibrationStatusMessage ?? "保存校准失败，请重试。"
                        presentCalibrationError(message: message)
                    }
            }

            calibrationGuidedFlowTask = nil
        }
    }

    private func startCalibrationSupportPollingIfNeeded() {
        guard appState.immersiveMode == .calibration else { return }
        guard calibrationSupportPollTask == nil else { return }

        calibrationSupportPollTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for _ in 0 ..< 40 {
                guard Task.isCancelled == false else { return }
                updateCalibrationTrackingStatusIfNeeded()
                if case .error = calibrationPhase { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            calibrationSupportPollTask = nil
        }
    }

    private func cancelCalibrationGuidedFlowTasks() {
        calibrationFlowBootstrapTask?.cancel()
        calibrationFlowBootstrapTask = nil
        calibrationGuidedFlowTask?.cancel()
        calibrationGuidedFlowTask = nil
        calibrationSupportPollTask?.cancel()
        calibrationSupportPollTask = nil
    }

    #if DEBUG
        func setCalibrationPhaseForPreview(_ phase: CalibrationPhase) {
            calibrationPhase = phase
        }
    #endif
}
