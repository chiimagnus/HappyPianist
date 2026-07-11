import ARKit
import Foundation
import Observation
import simd

@MainActor
@Observable
final class VirtualPianoPlacementViewModel {
    enum Presentation: Equatable {
        case hidden
        case placement
        case practice
    }

    private let appState: AppState
    private let practiceLocalizationViewModel: PracticeLocalizationViewModel
    private let gazePlaneHitTestService: any GazePlaneHitTestingProtocol
    private let virtualKeyboardPoseService: any VirtualKeyboardPoseServiceProtocol
    private let virtualPianoKeyGeometryService: any VirtualPianoKeyGeometryServiceProtocol

    let gazePlaneDiskConfirmation: GazePlaneDiskConfirmationViewModel

    var practiceSessionViewModel: PracticeSessionViewModel
    var isVirtualPianoEnabled = false
    private(set) var presentation: Presentation = .hidden
    var isVirtualPianoPlaced = false
    var latestDeviceWorldPosition: SIMD3<Float>?
    var latestGazePlaneHit: PlaneHit?
    var latestGazeRayOriginWorld: SIMD3<Float>?

    @ObservationIgnored private var virtualPianoGuidanceUpdateTask: Task<Void, Never>?

    init(
        appState: AppState,
        practiceSessionViewModel: PracticeSessionViewModel,
        practiceLocalizationViewModel: PracticeLocalizationViewModel,
        gazePlaneDiskConfirmation: GazePlaneDiskConfirmationViewModel? = nil,
        gazePlaneHitTestService: (any GazePlaneHitTestingProtocol)? = nil,
        virtualKeyboardPoseService: (any VirtualKeyboardPoseServiceProtocol)? = nil,
        virtualPianoKeyGeometryService: (any VirtualPianoKeyGeometryServiceProtocol)? = nil
    ) {
        self.appState = appState
        self.practiceSessionViewModel = practiceSessionViewModel
        self.practiceLocalizationViewModel = practiceLocalizationViewModel
        self.gazePlaneDiskConfirmation = gazePlaneDiskConfirmation ?? GazePlaneDiskConfirmationViewModel()
        self.gazePlaneHitTestService = gazePlaneHitTestService ?? GazePlaneHitTestService()
        self.virtualKeyboardPoseService = virtualKeyboardPoseService ?? VirtualKeyboardPoseService()
        self.virtualPianoKeyGeometryService = virtualPianoKeyGeometryService ?? VirtualPianoKeyGeometryService()
    }

    var arTrackingService: ARTrackingServiceProtocol {
        appState.arTrackingService
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

    func updatePracticeSession(_ practiceSessionViewModel: PracticeSessionViewModel) {
        self.practiceSessionViewModel = practiceSessionViewModel
    }

    func setPracticeVirtualPianoEnabled(_ isEnabled: Bool) {
        isVirtualPianoEnabled = isEnabled
        if isEnabled {
            practiceSessionViewModel.stopVirtualPianoInput()
            practiceSessionViewModel.clearCalibration()
            practiceLocalizationViewModel.shutdown()
            gazePlaneDiskConfirmation.reset()
            latestGazePlaneHit = nil
            startGuidanceIfNeeded()
            #if DEBUG && targetEnvironment(simulator)
                practiceLocalizationViewModel.setPracticeLocalizationState(.ready)
                if practiceSessionViewModel.keyboardGeometry == nil {
                    applyVirtualPianoGeometryAtDefaultPositionForSimulator()
                }
            #else
                if appState.cachedVirtualPianoWorldAnchorID == nil {
                    practiceLocalizationViewModel.setPracticeLocalizationState(.idle)
                }
            #endif
        } else {
            presentation = .hidden
            practiceSessionViewModel.stopVirtualPianoInput()
            practiceSessionViewModel.clearCalibration()
            practiceLocalizationViewModel.setPracticeLocalizationState(.idle)
            gazePlaneDiskConfirmation.reset()
            latestGazePlaneHit = nil
            stopGuidance()
        }
    }

    func showVirtualPianoForPlacement() {
        guard isVirtualPianoEnabled else { return }
        presentation = .placement
    }

    func showVirtualPianoForPractice() {
        guard isVirtualPianoEnabled else { return }
        presentation = .practice
    }

    func hideVirtualPiano() {
        presentation = .hidden
    }

    func retryPlacement() {
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

    func updateLatestDeviceWorldPosition(nowUptime: TimeInterval) {
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

    func startGuidanceIfNeeded() {
        guard appState.immersiveMode == .practice else { return }
        guard isVirtualPianoEnabled else { return }
        guard practiceSessionViewModel.keyboardGeometry == nil else { return }
        guard appState.immersiveSpaceState == .open else { return }
        guard virtualPianoGuidanceUpdateTask == nil else { return }

        virtualPianoGuidanceUpdateTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while Task.isCancelled == false {
                let nowUptime = ProcessInfo.processInfo.systemUptime
                updateGuidance(fingerTips: arTrackingService.fingerTipPositions, nowUptime: nowUptime)
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    func stopGuidance() {
        virtualPianoGuidanceUpdateTask?.cancel()
        virtualPianoGuidanceUpdateTask = nil
    }

    func updateGuidance(
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

        guard let worldFromKeyboard = virtualKeyboardPoseService.computeWorldFromKeyboard(
            planeWorldFromAnchor: planeWorldFromAnchor,
            handCenterOnPlaneWorld: handCenterOnPlaneWorld,
            deviceWorldTransform: deviceWorldTransform
        ) else { return }

        applyVirtualPianoGeometry(worldFromKeyboard: worldFromKeyboard)
    }

    private func applyVirtualPianoGeometry(worldFromKeyboard: simd_float4x4) {
        let frame = KeyboardFrame(worldFromKeyboard: worldFromKeyboard)
        if let geometry = virtualPianoKeyGeometryService.generateKeyboardGeometry(from: frame) {
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
                        // If persistence fails, the user can still play in this session.
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
}
