import Library
import Practice
import RealityKit
import SwiftUI

struct ImmersiveView: View {
    @Bindable var viewModel: ARGuideViewModel
    @Bindable var songLibraryViewModel: SongLibraryViewModel
    @Bindable var spatialLibraryViewModel: SpatialLibraryViewModel
    @State private var overlayController: PianoGuideOverlayController
    @State private var spatialLibrarySceneController: SpatialLibrarySceneController
    @GestureState private var spatialBrowseDragTranslation: CGFloat = 0
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
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    init(
        viewModel: ARGuideViewModel,
        songLibraryViewModel: SongLibraryViewModel,
        spatialLibraryViewModel: SpatialLibraryViewModel
    ) {
        self.viewModel = viewModel
        self.songLibraryViewModel = songLibraryViewModel
        self.spatialLibraryViewModel = spatialLibraryViewModel
        let keyEntityFactory = PianoKeyEntityFactory()
        _overlayController = State(
            initialValue: PianoGuideOverlayController(
                diagnosticsReporter: viewModel.diagnosticsReporter
            )
        )
        _spatialLibrarySceneController = State(
            initialValue: SpatialLibrarySceneController()
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
        RealityView { content, attachments in
            updateOverlays(content: content)
            updateSpatialLibrary(
                content: content,
                attachments: attachments
            )
        } update: { content, attachments in
            updateOverlays(content: content)
            updateSpatialLibrary(
                content: content,
                attachments: attachments
            )
        } attachments: {
            if viewModel.immersiveMode == .library,
               songLibraryViewModel.entries.isEmpty == false
            {
                if songLibraryViewModel.scorePreview.isOpen {
                    Attachment(id: SpatialLibraryAttachmentID.spread) {
                        SpatialLibrarySpreadAttachmentView(
                            library: songLibraryViewModel
                        )
                    }
                } else {
                    ForEach(spatialVisibleItems) { item in
                        if let entry = songLibraryViewModel.entries.first(
                            where: { $0.id == item.id }
                        ) {
                            Attachment(
                                id: SpatialLibraryAttachmentID.folio(item.id)
                            ) {
                                SpatialLibraryFolioAttachmentView(
                                    presentation: SongLibraryTrackPresentation(
                                        entry: entry,
                                        index: item.absoluteIndex
                                    ),
                                    isPlaying: songLibraryViewModel
                                        .isListeningPlaying(entryID: entry.id),
                                    onConfirm: {
                                        songLibraryViewModel.confirmFolio(
                                            entry.id
                                        )
                                    }
                                )
                            }
                        }
                    }
                }
            }
        }
        .gesture(
            spatialLibraryBrowseGesture,
            isEnabled: isSpatialBrowseGestureEnabled
        )
        .onAppear {
            updateDemonstrationHandsOverlayController()
            viewModel.onImmersiveAppear()
        }
        .onDisappear {
            songLibraryViewModel.scorePreview.close()
            resetOverlayControllers()
            spatialLibrarySceneController.reset()
            viewModel.onImmersiveDisappear()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                updateDemonstrationHandsOverlayController()
                viewModel.resumeImmersiveRuntimeIfNeeded()
            case .inactive, .background:
                songLibraryViewModel.scorePreview.close()
                resetOverlayControllers()
                spatialLibrarySceneController.reset()
                viewModel.suspendImmersiveRuntime()
            @unknown default:
                songLibraryViewModel.scorePreview.close()
                resetOverlayControllers()
                spatialLibrarySceneController.reset()
                viewModel.suspendImmersiveRuntime()
            }
        }
        .onChange(of: pianoDemonstrationHandsEnabled) {
            updateDemonstrationHandsOverlayController()
        }
        .onChange(of: viewModel.immersiveMode) {
            updateDemonstrationHandsOverlayController()
        }
        .onChange(of: viewModel.appState.arTrackingService.worldTrackingGeneration) {
            guard scenePhase == .active, viewModel.immersiveMode == .library else { return }
            spatialLibraryViewModel.enterLibraryMode()
        }
        .onChange(of: viewModel.appState.arTrackingService.providerStateByName["world"]) {
            guard scenePhase == .active, viewModel.immersiveMode == .library else { return }
            spatialLibraryViewModel.enterLibraryMode()
        }
        .onChange(of: songLibraryViewModel.entries.isEmpty) { _, isEmpty in
            guard isEmpty, viewModel.immersiveMode == .library else { return }
            Task { @MainActor in
                songLibraryViewModel.scorePreview.close()
                await viewModel.closeImmersive(using: makeImmersiveSpaceDismissHandler(dismissImmersiveSpace))
            }
        }
    }

    private var spatialVisibleItems: [SpatialLibraryVisibleItem] {
        SpatialLibraryVisibleSlice.items(
            orderedEntryIDs: songLibraryViewModel.entries.map(\.id),
            selectedEntryID: songLibraryViewModel.selectedEntryID
        )
    }

    private var spatialPlacement: SpatialLibraryPlacement? {
        guard case let .placed(placement) = spatialLibraryViewModel.state else {
            return nil
        }
        guard placement.worldTrackingGeneration == viewModel.appState.arTrackingService.worldTrackingGeneration,
              viewModel.appState.arTrackingService.providerStateByName["world"] == .running
        else { return nil }
        return placement
    }

    private var isSpatialBrowseGestureEnabled: Bool {
        viewModel.immersiveMode == .library
            && songLibraryViewModel.scorePreview.isOpen == false
            && spatialVisibleItems.count > 1
    }

    private var spatialLibraryBrowseGesture: some Gesture {
        DragGesture(minimumDistance: 16)
            .targetedToEntity(spatialLibrarySceneController.interactionEntity)
            .updating($spatialBrowseDragTranslation) { value, translation, _ in
                translation = value.gestureValue.translation.width
            }
            .onEnded { value in
                let translation = value.gestureValue.translation.width
                guard isSpatialBrowseGestureEnabled,
                      let direction = SpatialLibraryBrowseDecision.direction(
                          horizontalTranslation: translation
                      )
                else {
                    return
                }
                browseSpatialLibrary(direction: direction)
            }
    }

    private func browseSpatialLibrary(
        direction: SpatialLibraryBrowseDirection
    ) {
        guard let target = SpatialLibraryBrowseDecision.targetEntryID(
            orderedEntryIDs: songLibraryViewModel.entries.map(\.id),
            selectedEntryID: songLibraryViewModel.selectedEntryID,
            direction: direction
        ) else { return }
        songLibraryViewModel.selectEntry(target)
    }

    private func updateSpatialLibrary(
        content: RealityViewContent,
        attachments: RealityViewAttachments
    ) {
        let isActive = viewModel.immersiveMode == .library
            && songLibraryViewModel.entries.isEmpty == false

        spatialLibrarySceneController.update(
            isActive: isActive,
            placement: spatialPlacement,
            visibleItems: spatialVisibleItems,
            showsSpread: songLibraryViewModel.scorePreview.isOpen,
            browseDragProgress: SpatialLibraryBrowseDecision.progress(
                horizontalTranslation: spatialBrowseDragTranslation
            ),
            attachments: attachments,
            content: content
        )
    }

    private func updateOverlays(content: RealityViewContent) {
        guard viewModel.immersiveMode != .library else {
            resetOverlayControllers()
            return
        }
        let session = viewModel.practiceSessionViewModel
        let keyboardGeometry = session.keyboardGeometry
        let shouldShowPianoDemonstrationHands = pianoDemonstrationHandsEnabled
            && viewModel.immersiveMode == .practice

        calibrationOverlayController.update(
            showsReticle: shouldShowCalibrationReticle,
            reticlePoint: viewModel.calibrationCaptureService.reticlePoint,
            isReticleReadyToConfirm: viewModel.calibrationCaptureService.isReticleReadyToConfirm,
            a0TrackedAnchorPoint: viewModel.immersiveMode == .calibration ? viewModel.a0OverlayPoint : nil,
            c8TrackedAnchorPoint: viewModel.immersiveMode == .calibration ? viewModel.c8OverlayPoint : nil,
            content: content
        )
        keyboardAxesDebugOverlayController.update(
            isEnabled: debugKeyboardAxesOverlayEnabled,
            keyboardFrame: session.calibration?.keyboardFrame,
            content: content
        )
        guard viewModel.immersiveMode == .practice else {
            resetPracticeOverlayControllers()
            return
        }
        neonHandOverlayController.update(
            isEnabled: viewModel.immersiveMode == .practice,
            trackingService: viewModel.appState.arTrackingService,
            content: content
        )
        let pianoDemonstrationHandsTiming = session.pianoDemonstrationHandsTiming()
        let suppressedMIDINotes = pianoDemonstrationHandsOverlayController?.update(
            isEnabled: shouldShowPianoDemonstrationHands,
            motionClipSet: session.pianoDemonstrationMotionClipSet(
                for: pianoDemonstrationHandsTiming
            ),
            timing: pianoDemonstrationHandsTiming,
            keyboardGeometry: keyboardGeometry,
            content: content
        ) ?? []
        overlayController.updateHighlights(
            suppressedMIDINotes: suppressedMIDINotes,
            highlightGuide: session.currentPianoHighlightGuide,
            keyboardGeometry: keyboardGeometry,
            content: content
        )
        overlayController.updateRestorationEffect(event: session.latestFeedbackEvent)
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
            performanceSchedule: viewModel.latestAIPerformanceSchedule,
            content: content
        )
    }

    private func resetOverlayControllers() {
        calibrationOverlayController.reset()
        keyboardAxesDebugOverlayController.reset()
        resetPracticeOverlayControllers()
    }

    private func resetPracticeOverlayControllers() {
        overlayController.reset()
        neonHandOverlayController.reset()
        pianoDemonstrationHandsOverlayController?.reset()
        pianoDemonstrationHandsOverlayController = nil
        virtualPianoOverlayController.reset()
        gazePlaneDiskOverlayController.reset()
        virtualPerformerOverlayController.reset()
    }

    private func updateDemonstrationHandsOverlayController() {
        guard pianoDemonstrationHandsEnabled, viewModel.immersiveMode == .practice else {
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
    let songLibraryViewModel = LiveAppGraph.make().songLibraryViewModel
    ImmersiveView(
        viewModel: viewModel,
        songLibraryViewModel: songLibraryViewModel,
        spatialLibraryViewModel: viewModel.spatialLibraryViewModel
    )
}
