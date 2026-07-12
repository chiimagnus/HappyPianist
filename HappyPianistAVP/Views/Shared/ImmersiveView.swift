import RealityKit
import SwiftUI

struct ImmersiveView: View {
    @Bindable var viewModel: ARGuideViewModel
    @State private var overlayController = PianoGuideOverlayController()
    @State private var calibrationOverlayController = CalibrationOverlayController()
    @State private var keyboardAxesDebugOverlayController = KeyboardAxesDebugOverlayController()
    @State private var virtualPianoOverlayController = VirtualPianoOverlayController()
    @State private var gazePlaneDiskOverlayController = GazePlaneDiskOverlayController()
    @State private var virtualPerformerOverlayController = VirtualPerformerOverlayController()
    @AppStorage("debugKeyboardAxesOverlayEnabled") private var debugKeyboardAxesOverlayEnabled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private var shouldShowCalibrationReticle: Bool {
        guard viewModel.immersiveMode == .calibration else { return false }
        switch viewModel.calibrationPhase {
        case .completed, .error:
            return false
        default:
            return true
        }
    }

    var body: some View {
        let session = viewModel.practiceSessionViewModel
        let highlightGuide = session.currentPianoHighlightGuide
        let keyboardGeometry = session.keyboardGeometry
        let keyboardFrame = session.calibration?.keyboardFrame

        RealityView { content in
            calibrationOverlayController.update(
                showsReticle: shouldShowCalibrationReticle,
                reticlePoint: viewModel.calibrationCaptureService.reticlePoint,
                isReticleReadyToConfirm: viewModel.calibrationCaptureService.isReticleReadyToConfirm,
                a0TrackedAnchorPoint: viewModel.a0OverlayPoint,
                c8TrackedAnchorPoint: viewModel.c8OverlayPoint,
                content: content
            )
            keyboardAxesDebugOverlayController.update(
                isEnabled: debugKeyboardAxesOverlayEnabled,
                keyboardFrame: keyboardFrame,
                content: content
            )
            overlayController.updateHighlights(
                highlightGuide: highlightGuide,
                keyboardGeometry: keyboardGeometry,
                content: content
            )
            overlayController.updateRestorationEffect(event: session.latestFeedbackEvent, reduceMotion: reduceMotion)
            gazePlaneDiskOverlayController.update(
                isVisible: viewModel.isGazePlaneDiskVisible,
                diskWorldTransform: viewModel.gazePlaneDiskWorldTransform,
                statusText: viewModel.gazePlaneDiskOverlayText,
                cameraWorldPosition: viewModel.gazePlaneDiskCameraWorldPosition,
                content: content
            )
            virtualPianoOverlayController.update(
                isEnabled: viewModel.shouldShowVirtualPiano,
                keyboardGeometry: keyboardGeometry,
                content: content
            )
            virtualPerformerOverlayController.update(
                isEnabled: viewModel.isVirtualPerformerEnabled,
                isPerforming: viewModel.isAIPerformanceActive,
                keyboardGeometry: keyboardGeometry,
                cameraWorldPosition: viewModel.latestDeviceWorldPosition,
                performanceSchedule: viewModel.latestAIPerformanceSchedule,
                content: content
            )
        } update: { content in
            calibrationOverlayController.update(
                showsReticle: shouldShowCalibrationReticle,
                reticlePoint: viewModel.calibrationCaptureService.reticlePoint,
                isReticleReadyToConfirm: viewModel.calibrationCaptureService.isReticleReadyToConfirm,
                a0TrackedAnchorPoint: viewModel.a0OverlayPoint,
                c8TrackedAnchorPoint: viewModel.c8OverlayPoint,
                content: content
            )
            keyboardAxesDebugOverlayController.update(
                isEnabled: debugKeyboardAxesOverlayEnabled,
                keyboardFrame: keyboardFrame,
                content: content
            )
            overlayController.updateHighlights(
                highlightGuide: highlightGuide,
                keyboardGeometry: keyboardGeometry,
                content: content
            )
            overlayController.updateRestorationEffect(event: session.latestFeedbackEvent, reduceMotion: reduceMotion)
            gazePlaneDiskOverlayController.update(
                isVisible: viewModel.isGazePlaneDiskVisible,
                diskWorldTransform: viewModel.gazePlaneDiskWorldTransform,
                statusText: viewModel.gazePlaneDiskOverlayText,
                cameraWorldPosition: viewModel.gazePlaneDiskCameraWorldPosition,
                content: content
            )
            virtualPianoOverlayController.update(
                isEnabled: viewModel.shouldShowVirtualPiano,
                keyboardGeometry: keyboardGeometry,
                content: content
            )
            virtualPerformerOverlayController.update(
                isEnabled: viewModel.isVirtualPerformerEnabled,
                isPerforming: viewModel.isAIPerformanceActive,
                keyboardGeometry: keyboardGeometry,
                cameraWorldPosition: viewModel.latestDeviceWorldPosition,
                performanceSchedule: viewModel.latestAIPerformanceSchedule,
                content: content
            )
        }
        .onAppear {
            viewModel.onImmersiveAppear()
        }
        .onDisappear {
            overlayController.reset()
            viewModel.onImmersiveDisappear()
        }
        .onChange(of: scenePhase) {
            if scenePhase != .active {
                overlayController.reset()
            }
        }
    }
}

#Preview(immersionStyle: .mixed) {
    let worldAnchorCalibrationStore = WorldAnchorCalibrationStore()
    let keyGeometryService = PianoKeyGeometryService()
    let arTrackingService = ARTrackingService()
    let calibrationCaptureService = CalibrationPointCaptureService()
    let calibrationRepository = CalibrationRepository(worldAnchorCalibrationStore: worldAnchorCalibrationStore)
    let pianoModeRegistry: PianoModeRegistryProtocol = PianoModeRegistryService(modes: [])
    let makePracticeSessionViewModel: @MainActor (String?) -> PracticeSessionViewModel = { _ in fatalError("preview only") }
    let practiceSetupState = PracticeSetupState()
    let appState = AppState(
        arTrackingService: arTrackingService,
        calibrationCaptureService: calibrationCaptureService,
        calibrationRepository: calibrationRepository,
        keyGeometryService: keyGeometryService
    )
    let viewModel = ARGuideViewModel(
        appState: appState,
        practiceSetupState: practiceSetupState,
        pianoModeRegistry: pianoModeRegistry,
        makePracticeSessionViewModel: makePracticeSessionViewModel
    )
    ImmersiveView(viewModel: viewModel)
}
