import ARKit
import Foundation
import Observation
import SwiftUI
import simd

@MainActor
@Observable
final class ARGuideViewModel {
    enum PracticeLocalizationFailure: Equatable {
        case missingImportedSteps
        case missingStoredCalibration
        case worldSensingDenied
        case handTrackingDenied
        case worldTrackingUnsupported
        case providerNotRunning(state: String)
        case anchorMissing(id: UUID)
        case anchorNotTracked(id: UUID, waitedSeconds: Int)
        case immersiveOpenFailed(message: String)

        var message: String {
            switch self {
            case .missingImportedSteps:
                return "请先导入 MusicXML。"
            case .missingStoredCalibration:
                return "未发现校准数据，请先 Step 1 校准。"
            case .worldSensingDenied:
                return "无法定位：World Sensing 权限未授权（请在系统设置中允许本 App 访问）。"
            case .handTrackingDenied:
                return "无法定位：Hand Tracking 权限未授权（请在系统设置中允许本 App 访问）。"
            case .worldTrackingUnsupported:
                return "无法定位：此环境不支持 World Tracking。"
            case .providerNotRunning(let state):
                return "无法定位：WorldTrackingProvider 未运行（state=\(state)）。"
            case .anchorMissing(let id):
                return "无法定位：未在当前环境恢复已保存的锚点（id=\(id.uuidString)）。"
            case .anchorNotTracked(let id, let waitedSeconds):
                return "无法定位：锚点存在但尚未追踪（id=\(id.uuidString)，已等待 \(waitedSeconds) 秒）。"
            case .immersiveOpenFailed(let message):
                return message
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

    private let appModel: AppModel
    private var handTrackingConsumerTask: Task<Void, Never>?
    private var calibrationAnchorCaptureTask: Task<Void, Never>?
    private var practiceLocalizationTask: Task<Void, Never>?
    private var hasStartedGuidingInCurrentImmersiveSession = false
    private var wasRightHandPinching = false
    private let providerStartupTimeoutSeconds = 5
    private let practiceLocalizationTimeoutSeconds = 5
    private let practiceLocalizationPollingIntervalNanoseconds: UInt64 = 250_000_000

    private(set) var practiceLocalizationState: PracticeLocalizationState = .idle

    init(appModel: AppModel) {
        self.appModel = appModel
    }

    var calibration: PianoCalibration? {
        appModel.calibration
    }

    var storedCalibration: StoredWorldAnchorCalibration? {
        appModel.storedCalibration
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
        get { appModel.pendingCalibrationCaptureAnchor }
        set { appModel.pendingCalibrationCaptureAnchor = newValue }
    }

    var calibrationStatusMessage: String? {
        get { appModel.calibrationStatusMessage }
        set { appModel.calibrationStatusMessage = newValue }
    }

    var calibrationCaptureService: CalibrationPointCaptureService {
        appModel.calibrationCaptureService
    }

    var practiceSessionViewModel: PracticeSessionViewModel {
        appModel.practiceSessionViewModel
    }

    var arTrackingService: ARTrackingServiceProtocol {
        appModel.arTrackingService
    }

    var hasImportedSteps: Bool {
        appModel.importedSteps.isEmpty == false
    }

    var immersiveMode: AppModel.ImmersiveMode {
        appModel.immersiveMode
    }

    var immersiveSpaceState: AppModel.ImmersiveSpaceState {
        appModel.immersiveSpaceState
    }

    func saveCalibration() {
        appModel.saveCalibrationIfPossible()
    }

    func beginCalibrationRecapture() {
        appModel.beginCalibrationRecapture()
    }

    func skipStep() {
        practiceSessionViewModel.skip()
    }

    func markCorrect() {
        practiceSessionViewModel.markCorrect()
    }

    var practiceLocalizationStatusText: String? {
        switch practiceLocalizationState {
        case .idle:
            return nil
        case .blocked(let reason), .failed(let reason):
            return reason.message
        case .openingImmersive:
            return "正在打开沉浸空间…"
        case .waitingForProviders:
            return "正在启动追踪服务…"
        case .locating(let elapsedSeconds, let totalSeconds):
            return "正在定位钢琴…（\(elapsedSeconds)/\(totalSeconds)s）"
        case .ready:
            return "定位成功，已开始引导。"
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
        case .blocked(let blockingReason), .failed(let blockingReason):
            reason = blockingReason
        default:
            return false
        }

        switch reason {
        case .missingStoredCalibration, .anchorMissing, .anchorNotTracked:
            return true
        default:
            return false
        }
    }

    func practiceEntryBlockingReason() -> PracticeLocalizationFailure? {
        if hasImportedSteps == false {
            return .missingImportedSteps
        }

        if storedCalibration == nil {
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
        mode: AppModel.ImmersiveMode,
        using openImmersiveSpace: OpenImmersiveSpaceAction
    ) async -> String? {
        appModel.immersiveMode = mode

        switch appModel.immersiveSpaceState {
        case .open:
            return nil

        case .inTransition:
            for _ in 0..<40 {
                await Task.yield()
                if appModel.immersiveSpaceState != .inTransition {
                    break
                }
            }

            if appModel.immersiveSpaceState == .closed {
                return await openImmersiveForStep(mode: mode, using: openImmersiveSpace)
            }
            return nil

        case .closed:
            appModel.immersiveSpaceState = .inTransition
            switch await openImmersiveSpace(id: appModel.immersiveSpaceID) {
            case .opened:
                // Don't set immersiveSpaceState to .open here.
                // ImmersiveView.onAppear is the single source of truth.
                return nil

            case .userCancelled:
                appModel.immersiveSpaceState = .closed
                return "已取消打开沉浸空间。"

            case .error:
                appModel.immersiveSpaceState = .closed
                return "打开沉浸空间失败，请重试。"

            @unknown default:
                appModel.immersiveSpaceState = .closed
                return "沉浸空间返回未知状态，请重试。"
            }
        }
    }

    func closeImmersiveForStep(using dismissImmersiveSpace: DismissImmersiveSpaceAction) async {
        guard appModel.immersiveSpaceState != .closed else { return }
        if appModel.immersiveSpaceState == .open {
            appModel.immersiveSpaceState = .inTransition
        }
        await dismissImmersiveSpace()
        // Don't set immersiveSpaceState to .closed here.
        // ImmersiveView.onDisappear is the single source of truth.
    }

    func recoverImmersiveStateIfStuck() async {
        guard appModel.immersiveSpaceState == .inTransition else { return }
        for _ in 0..<40 {
            await Task.yield()
            if appModel.immersiveSpaceState != .inTransition {
                return
            }
        }
        appModel.immersiveSpaceState = .closed
    }

    func onImmersiveAppear() {
        switch appModel.immersiveMode {
        case .calibration:
            hasStartedGuidingInCurrentImmersiveSession = false
            wasRightHandPinching = false
            startHandTrackingIfNeeded()
            if calibrationStatusMessage == nil,
               arTrackingService.providerStateByName["hand"] == .unsupported {
                calibrationStatusMessage = "手部追踪不可用：此设备不支持手部追踪。"
            }

        case .practice:
            startHandTrackingIfNeeded()
        }
    }

    func onImmersiveDisappear() {
        cancelPracticeLocalizationTask()
        hasStartedGuidingInCurrentImmersiveSession = false
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
                switch self.appModel.immersiveMode {
                case .calibration:
                    self.handleCalibrationHandUpdates()
                case .practice:
                    _ = self.practiceSessionViewModel.handleFingerTipPositions(fingerTips)
                }
            }
        }
    }

    private func handleCalibrationHandUpdates() {
        let nowUptime = ProcessInfo.processInfo.systemUptime
        calibrationCaptureService.updateReticleFromHandTracking(
            arTrackingService.leftIndexFingerTipPosition,
            nowUptime: nowUptime
        )

        let isRightHandPinching: Bool = {
            guard
                let rightIndex = arTrackingService.rightIndexFingerTipPosition,
                let rightThumb = arTrackingService.rightThumbTipPosition
            else {
                return false
            }
            let pinchDistanceThresholdMeters: Float = 0.018
            return simd_length(rightIndex - rightThumb) < pinchDistanceThresholdMeters
        }()

        if isRightHandPinching, wasRightHandPinching == false {
            calibrationAnchorCaptureTask?.cancel()
            calibrationAnchorCaptureTask = Task { @MainActor [weak self] in
                guard let self else { return }
                await self.confirmPendingCalibrationAnchorIfReady()
                self.calibrationAnchorCaptureTask = nil
            }
        }
        wasRightHandPinching = isRightHandPinching
    }

    private func confirmPendingCalibrationAnchorIfReady() async {
        guard let pendingAnchor = pendingCalibrationCaptureAnchor else { return }
        guard calibrationCaptureService.isReticleReadyToConfirm else {
            calibrationStatusMessage = "请先将左手食指放稳在 \(pendingAnchor == .a0 ? "A0" : "C8") 键上（等待准星变绿），再用右手捏合确认。"
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

            if let oldAnchorID,
               oldAnchorID != worldAnchor.id,
               let oldAnchor = arTrackingService.worldAnchorsByID[oldAnchorID] {
                try? await arTrackingService.worldTrackingProvider.removeAnchor(oldAnchor)
            }
        } catch {
            calibrationStatusMessage = "锁定失败：\(error.localizedDescription)"
        }
    }

    func stopHandTracking() {
        calibrationAnchorCaptureTask?.cancel()
        calibrationAnchorCaptureTask = nil
        handTrackingConsumerTask?.cancel()
        handTrackingConsumerTask = nil
        arTrackingService.stop()
    }

    var practiceStatusText: String {
        switch practiceSessionViewModel.state {
        case .idle:
            return "练习：空闲"
        case .ready:
            return "练习：就绪"
        case .guiding(let index):
            return "练习：引导中（第 \(index + 1) 步）"
        case .completed:
            return "练习：已完成"
        }
    }

    var practiceProgressText: String {
        guard appModel.importedSteps.isEmpty == false else { return "0 / 0" }
        let total = appModel.importedSteps.count
        let completedCount = min(practiceSessionViewModel.currentStepIndex, total)
        return "\(completedCount) / \(total)"
    }

    var canControlPractice: Bool {
        guard hasStartedGuidingInCurrentImmersiveSession else { return false }

        switch practiceSessionViewModel.state {
        case .guiding:
            return true
        default:
            return false
        }
    }

    private func beginPracticeLocalization(
        using openImmersiveSpace: OpenImmersiveSpaceAction,
        dismissImmersiveSpace: DismissImmersiveSpaceAction
    ) async {
        cancelPracticeLocalizationTask()
        hasStartedGuidingInCurrentImmersiveSession = false
        appModel.clearRuntimeCalibrationForPracticeRelocation()

        guard let blockingReason = practiceEntryBlockingReason() else {
            practiceLocalizationState = .openingImmersive
            if let openError = await openImmersiveForStep(mode: .practice, using: openImmersiveSpace) {
                practiceLocalizationState = .failed(reason: .immersiveOpenFailed(message: openError))
                return
            }

            practiceLocalizationTask = Task { @MainActor [weak self] in
                guard let self else { return }
                await self.runPracticeLocalization(dismissImmersiveSpace: dismissImmersiveSpace)
                self.practiceLocalizationTask = nil
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
        var lastRecoverableResolution: AppModel.PracticeCalibrationResolutionResult?

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

            switch appModel.resolveRuntimeCalibrationFromTrackedAnchors() {
            case .resolved:
                practiceLocalizationState = .ready
                practiceSessionViewModel.startGuidingIfReady()
                hasStartedGuidingInCurrentImmersiveSession = true
                return

            case .missingStoredCalibration:
                await handlePracticeLocalizationFailure(.missingStoredCalibration, dismissImmersiveSpace: dismissImmersiveSpace)
                return

            case .anchorMissing(let id):
                lastRecoverableResolution = .anchorMissing(id: id)

            case .anchorNotTracked(let id):
                lastRecoverableResolution = .anchorNotTracked(id: id)
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
        lastRecoverableResolution: AppModel.PracticeCalibrationResolutionResult?
    ) -> PracticeLocalizationFailure {
        guard let lastRecoverableResolution else {
            return .providerNotRunning(state: currentProviderStateSummary())
        }

        switch lastRecoverableResolution {
        case .anchorMissing(let id):
            return .anchorMissing(id: id)
        case .anchorNotTracked(let id):
            return .anchorNotTracked(
                id: id,
                waitedSeconds: practiceLocalizationTimeoutSeconds
            )
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
            let handState = arTrackingService.providerStateByName["hand"] ?? .idle

            if worldState == .running, handState == .running {
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

        if let worldAuthorizationStatus = arTrackingService.authorizationStatusByType[.worldSensing],
           worldAuthorizationStatus != .allowed {
            return .worldSensingDenied
        }

        if let handAuthorizationStatus = arTrackingService.authorizationStatusByType[.handTracking],
           handAuthorizationStatus != .allowed {
            return .handTrackingDenied
        }

        if let worldState = arTrackingService.providerStateByName["world"] {
            switch worldState {
            case .unsupported:
                return .worldTrackingUnsupported
            case .unauthorized:
                return .worldSensingDenied
            case .failed(let reason):
                return .providerNotRunning(state: "world=failed(\(reason))")
            default:
                break
            }
        }

        if let handState = arTrackingService.providerStateByName["hand"] {
            switch handState {
            case .unauthorized:
                return .handTrackingDenied
            case .failed(let reason):
                return .providerNotRunning(state: "hand=failed(\(reason))")
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
        hasStartedGuidingInCurrentImmersiveSession = false
        appModel.clearRuntimeCalibrationForPracticeRelocation()

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
}
