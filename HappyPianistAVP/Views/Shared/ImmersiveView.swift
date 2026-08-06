import Practice
import RealityKit
import SwiftUI

struct ImmersiveView: View {
    @Bindable var viewModel: ARGuideViewModel
    @State private var overlayController: PianoGuideOverlayController
    @State private var calibrationOverlayController = CalibrationOverlayController()
    @State private var keyboardAxesDebugOverlayController = KeyboardAxesDebugOverlayController()
    @State private var neonHandOverlayController = NeonHandOverlayController()
    @State private var pianoDemonstrationHandsOverlayController: PianoDemonstrationHandsOverlayController?
    @State private var virtualPianoOverlayController: VirtualPianoOverlayController
    @State private var gazePlaneDiskOverlayController = GazePlaneDiskOverlayController()
    @State private var virtualPerformerOverlayController: VirtualPerformerOverlayController
    @AppStorage("debugKeyboardAxesOverlayEnabled") private var debugKeyboardAxesOverlayEnabled = false
    @AppStorage(PianoDemonstrationHandsSettings.userDefaultsKey)
    private var pianoDemonstrationHandsEnabled = PianoDemonstrationHandsSettings.defaultValue
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    init(viewModel: ARGuideViewModel) {
        self.viewModel = viewModel
        let keyEntityFactory = PianoKeyEntityFactory()
        _overlayController = State(
            initialValue: PianoGuideOverlayController(
                diagnosticsReporter: viewModel.diagnosticsReporter
            )
        )
        _virtualPianoOverlayController = State(
            initialValue: VirtualPianoOverlayController(keyEntityFactory: keyEntityFactory)
        )
        _virtualPerformerOverlayController = State(
            initialValue: VirtualPerformerOverlayController(
                keyEntityFactory: keyEntityFactory,
                diagnosticsReporter: viewModel.diagnosticsReporter
            )
        )
    }

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
        RealityView { content in
            updateOverlays(content: content)
        } update: { content in
            updateOverlays(content: content)
        }
        .onAppear {
            updateDemonstrationHandsOverlayController()
            viewModel.onImmersiveAppear()
        }
        .onDisappear {
            resetOverlayControllers()
            viewModel.onImmersiveDisappear()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                updateDemonstrationHandsOverlayController()
                viewModel.resumeImmersiveRuntimeIfNeeded()
            case .inactive, .background:
                resetOverlayControllers()
                viewModel.suspendImmersiveRuntime()
            @unknown default:
                resetOverlayControllers()
                viewModel.suspendImmersiveRuntime()
            }
        }
        .onChange(of: pianoDemonstrationHandsEnabled) {
            updateDemonstrationHandsOverlayController()
        }
    }

    private func updateOverlays(content: RealityViewContent) {
        let session = viewModel.practiceSessionViewModel
        let keyboardGeometry = session.keyboardGeometry
        let shouldShowPianoDemonstrationHands = pianoDemonstrationHandsEnabled
            && viewModel.immersiveMode == .practice

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
            keyboardFrame: session.calibration?.keyboardFrame,
            content: content
        )
        neonHandOverlayController.update(
            isEnabled: viewModel.immersiveMode == .practice,
            trackingService: viewModel.appState.arTrackingService,
            reduceMotion: reduceMotion,
            content: content
        )
        pianoDemonstrationHandsOverlayController?.update(
            isEnabled: shouldShowPianoDemonstrationHands,
            highlightGuide: session.currentPianoHighlightGuide,
            keyboardGeometry: keyboardGeometry,
            reduceMotion: reduceMotion,
            content: content
        )
        overlayController.updateHighlights(
            isEnabled: shouldShowPianoDemonstrationHands == false,
            highlightGuide: session.currentPianoHighlightGuide,
            keyboardGeometry: keyboardGeometry,
            differentiateWithoutColor: differentiateWithoutColor,
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
            reduceMotion: reduceMotion,
            content: content
        )
        virtualPerformerOverlayController.update(
            isEnabled: viewModel.isVirtualPerformerEnabled,
            isPerforming: viewModel.isAIPerformanceActive,
            keyboardGeometry: keyboardGeometry,
            reduceMotion: reduceMotion,
            performanceSchedule: viewModel.latestAIPerformanceSchedule,
            content: content
        )
    }

    private func resetOverlayControllers() {
        overlayController.reset()
        calibrationOverlayController.reset()
        keyboardAxesDebugOverlayController.reset()
        neonHandOverlayController.reset()
        pianoDemonstrationHandsOverlayController?.reset()
        pianoDemonstrationHandsOverlayController = nil
        virtualPianoOverlayController.reset()
        gazePlaneDiskOverlayController.reset()
        virtualPerformerOverlayController.reset()
    }

    private func updateDemonstrationHandsOverlayController() {
        guard pianoDemonstrationHandsEnabled else {
            pianoDemonstrationHandsOverlayController?.reset()
            pianoDemonstrationHandsOverlayController = nil
            return
        }

        if pianoDemonstrationHandsOverlayController?.requiresReplacement == true {
            pianoDemonstrationHandsOverlayController = nil
        }
        if pianoDemonstrationHandsOverlayController == nil {
            pianoDemonstrationHandsOverlayController = PianoDemonstrationHandsOverlayController(
                diagnosticsReporter: viewModel.diagnosticsReporter
            )
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
