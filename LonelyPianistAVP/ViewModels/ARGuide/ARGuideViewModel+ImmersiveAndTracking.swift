import ARKit
import Foundation
import Observation
import os
import simd

extension ARGuideViewModel {
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
        func applyVirtualPianoGeometryAtDefaultPositionForSimulator() {
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

    func startVirtualPianoGuidanceIfNeeded() {
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

    func stopVirtualPianoGuidance() {
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
