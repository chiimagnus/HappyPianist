import Foundation
import Observation

@MainActor
@Observable
final class PracticeLocalizationViewModel {
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
                    "校准数据异常：A0 与 C8 距离过近（\(distanceMeters.formatted(.number.precision(.fractionLength(3))))m）。请返回 Step 1 重新校准。"
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
    private let arTrackingService: ARTrackingServiceProtocol
    private let providerStartupTimeoutSeconds: Int
    private let practiceLocalizationTimeoutSeconds: Int
    private let pollingInterval: Duration

    private var practiceLocalizationTask: Task<Void, Never>?

    private(set) var practiceLocalizationState: PracticeLocalizationState = .idle

    init(
        appState: AppState,
        providerStartupTimeoutSeconds: Int = 5,
        practiceLocalizationTimeoutSeconds: Int = 5,
        pollingInterval: Duration = .milliseconds(250)
    ) {
        self.appState = appState
        arTrackingService = appState.arTrackingService
        self.providerStartupTimeoutSeconds = providerStartupTimeoutSeconds
        self.practiceLocalizationTimeoutSeconds = practiceLocalizationTimeoutSeconds
        self.pollingInterval = pollingInterval
    }

    func shutdown() {
        cancelPracticeLocalizationTask()
    }

    func setPracticeLocalizationState(_ state: PracticeLocalizationState) {
        practiceLocalizationState = state
    }

    func resetPracticeLocalizationState() {
        cancelPracticeLocalizationTask()
        practiceLocalizationState = .idle
    }

    func beginPracticeLocalization(
        isVirtualPianoEnabled: Bool,
        blockingReason: PracticeLocalizationFailure?,
        openImmersiveSpace: PracticeImmersiveOpenHandler,
        dismissImmersiveSpace: @escaping PracticeImmersiveDismissHandler,
        openImmersiveForStep: @escaping (PracticeImmersiveOpenHandler) async -> String?,
        closeImmersiveForStep: @escaping (PracticeImmersiveDismissHandler) async -> Void,
        recoverImmersiveStateIfStuck: @escaping () async -> Void
    ) async {
        cancelPracticeLocalizationTask()
        if isVirtualPianoEnabled == false {
            appState.clearRuntimeCalibrationForPracticeRelocation()
        }

        guard let blockingReason else {
            practiceLocalizationState = .openingImmersive
            if let openError = await openImmersiveForStep(openImmersiveSpace) {
                practiceLocalizationState = .failed(reason: .immersiveOpenFailed(message: openError))
                return
            }

            if isVirtualPianoEnabled {
                practiceLocalizationState = .ready
                return
            }

            practiceLocalizationTask = Task { @MainActor [weak self] in
                guard let self else { return }
                await runPracticeLocalization(
                    closeImmersiveForStep: closeImmersiveForStep,
                    dismissImmersiveSpace: dismissImmersiveSpace,
                    recoverImmersiveStateIfStuck: recoverImmersiveStateIfStuck
                )
                practiceLocalizationTask = nil
            }
            return
        }

        practiceLocalizationState = .blocked(reason: blockingReason)
    }

    private func runPracticeLocalization(
        closeImmersiveForStep: @escaping (PracticeImmersiveDismissHandler) async -> Void,
        dismissImmersiveSpace: @escaping PracticeImmersiveDismissHandler,
        recoverImmersiveStateIfStuck: @escaping () async -> Void
    ) async {
        practiceLocalizationState = .waitingForProviders

        if let startupFailure = await waitForProvidersToRunOrFail() {
            guard Task.isCancelled == false else { return }
            await handlePracticeLocalizationFailure(
                startupFailure,
                closeImmersiveForStep: closeImmersiveForStep,
                dismissImmersiveSpace: dismissImmersiveSpace,
                recoverImmersiveStateIfStuck: recoverImmersiveStateIfStuck
            )
            return
        }

        let startedAt = ProcessInfo.processInfo.systemUptime
        var lastRecoverableResolution: AppState.PracticeCalibrationResolutionResult?

        while Task.isCancelled == false {
            if let hardFailure = immediatePracticeFailureReason() {
                await handlePracticeLocalizationFailure(
                    hardFailure,
                    closeImmersiveForStep: closeImmersiveForStep,
                    dismissImmersiveSpace: dismissImmersiveSpace,
                    recoverImmersiveStateIfStuck: recoverImmersiveStateIfStuck
                )
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
                        closeImmersiveForStep: closeImmersiveForStep,
                        dismissImmersiveSpace: dismissImmersiveSpace,
                        recoverImmersiveStateIfStuck: recoverImmersiveStateIfStuck
                    )
                    return

                case let .anchorMissing(id):
                    lastRecoverableResolution = .anchorMissing(id: id)

                case let .anchorNotTracked(id):
                    lastRecoverableResolution = .anchorNotTracked(id: id)

                case let .anchorsTooClose(distanceMeters):
                    await handlePracticeLocalizationFailure(
                        .anchorsTooClose(distanceMeters: distanceMeters),
                        closeImmersiveForStep: closeImmersiveForStep,
                        dismissImmersiveSpace: dismissImmersiveSpace,
                        recoverImmersiveStateIfStuck: recoverImmersiveStateIfStuck
                    )
                    return

                case .devicePoseUnavailable:
                    lastRecoverableResolution = .devicePoseUnavailable
            }

            if elapsed >= Double(practiceLocalizationTimeoutSeconds) {
                break
            }

            try? await Task.sleep(for: pollingInterval)
        }

        guard Task.isCancelled == false else { return }

        let timeoutFailure = practiceLocalizationTimeoutFailure(
            lastRecoverableResolution: lastRecoverableResolution
        )

        await handlePracticeLocalizationFailure(
            timeoutFailure,
            closeImmersiveForStep: closeImmersiveForStep,
            dismissImmersiveSpace: dismissImmersiveSpace,
            recoverImmersiveStateIfStuck: recoverImmersiveStateIfStuck
        )
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

            try? await Task.sleep(for: pollingInterval)
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
        closeImmersiveForStep: (PracticeImmersiveDismissHandler) async -> Void,
        dismissImmersiveSpace: @escaping PracticeImmersiveDismissHandler,
        recoverImmersiveStateIfStuck: () async -> Void
    ) async {
        guard Task.isCancelled == false else { return }

        practiceLocalizationState = .failed(reason: failure)
        appState.clearRuntimeCalibrationForPracticeRelocation()

        await closeImmersiveForStep(dismissImmersiveSpace)
        await recoverImmersiveStateIfStuck()
    }

    private func cancelPracticeLocalizationTask() {
        practiceLocalizationTask?.cancel()
        practiceLocalizationTask = nil
    }
}
