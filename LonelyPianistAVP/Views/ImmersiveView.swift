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
    @State private var panoramaBackgroundEntity: ModelEntity?
    @State private var panoramaLoadedFileName: String?
    @State private var panoramaLoadTask: Task<Void, Never>?

    private var desiredPanoramaBaseName: String? {
        guard let songName = viewModel.importedSongDisplayName, songName.isEmpty == false else {
            return nil
        }
        return songName
    }

    private func loadPanoramaIfNeeded() {
        let desiredBaseName = desiredPanoramaBaseName

        if panoramaLoadedFileName == desiredBaseName {
            return
        }

        panoramaLoadTask?.cancel()
        panoramaLoadTask = nil

        let url: URL?
        if let desiredBaseName {
            url = Bundle.main.url(forResource: desiredBaseName, withExtension: "jpg", subdirectory: "fullspace")
                ?? Bundle.main.url(forResource: desiredBaseName, withExtension: "jpg")
                ?? Bundle.main.url(forResource: desiredBaseName, withExtension: "jpeg", subdirectory: "fullspace")
                ?? Bundle.main.url(forResource: desiredBaseName, withExtension: "jpeg")
                ?? Bundle.main.url(forResource: desiredBaseName, withExtension: "png", subdirectory: "fullspace")
                ?? Bundle.main.url(forResource: desiredBaseName, withExtension: "png")
        } else {
            url = nil
        }

        panoramaLoadedFileName = desiredBaseName
        guard let url else {
            if let panoramaBackgroundEntity {
                var material = UnlitMaterial(color: UIColor.white)
                material.faceCulling = .front
                panoramaBackgroundEntity.model?.materials = [material]
            }
            return
        }

        let requestedBaseName = desiredBaseName
        panoramaLoadTask = Task { [weak panoramaBackgroundEntity] in
            let texture = try? await TextureResource(contentsOf: url)
            guard let texture else { return }
            guard Task.isCancelled == false else { return }

            var texturedMaterial = UnlitMaterial()
            texturedMaterial.color = .init(tint: UIColor.white, texture: .init(texture))
            texturedMaterial.faceCulling = .front

            await MainActor.run {
                guard panoramaLoadedFileName == requestedBaseName else { return }
                panoramaBackgroundEntity?.model?.materials = [texturedMaterial]
                panoramaLoadTask = nil
            }
        }
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
            if panoramaBackgroundEntity == nil {
                let sphereMesh = MeshResource.generateSphere(radius: 100.0)
                var material = UnlitMaterial(color: UIColor.white)
                material.faceCulling = .front

                let entity = ModelEntity(mesh: sphereMesh, materials: [material])
                entity.orientation = simd_quatf(angle: Float.pi, axis: SIMD3<Float>(0, 1, 0))
                content.add(entity)
                panoramaBackgroundEntity = entity
            }

            loadPanoramaIfNeeded()

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
                keyboardFrame: viewModel.practiceSessionViewModel.calibration?.keyboardFrame,
                content: content
            )
            overlayController.updateHighlights(
                highlightGuide: viewModel.practiceSessionViewModel.currentPianoHighlightGuide,
                keyboardGeometry: viewModel.practiceSessionViewModel.keyboardGeometry,
                content: content
            )
            gazePlaneDiskOverlayController.update(
                isVisible: viewModel.isGazePlaneDiskVisible,
                diskWorldTransform: viewModel.gazePlaneDiskWorldTransform,
                statusText: viewModel.gazePlaneDiskOverlayText,
                cameraWorldPosition: viewModel.gazePlaneDiskCameraWorldPosition,
                content: content
            )
            virtualPianoOverlayController.update(
                isEnabled: viewModel.isVirtualPianoEnabled,
                keyboardGeometry: viewModel.practiceSessionViewModel.keyboardGeometry,
                content: content
            )
            virtualPerformerOverlayController.update(
                isEnabled: viewModel.isVirtualPerformerEnabled,
                isPerforming: viewModel.isAIPerformanceActive,
                keyboardGeometry: viewModel.practiceSessionViewModel.keyboardGeometry,
                cameraWorldPosition: viewModel.latestDeviceWorldPosition,
                performanceSchedule: viewModel.latestAIPerformanceSchedule,
                content: content
            )
        } update: { content in
            loadPanoramaIfNeeded()

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
                keyboardFrame: viewModel.practiceSessionViewModel.calibration?.keyboardFrame,
                content: content
            )
            overlayController.updateHighlights(
                highlightGuide: viewModel.practiceSessionViewModel.currentPianoHighlightGuide,
                keyboardGeometry: viewModel.practiceSessionViewModel.keyboardGeometry,
                content: content
            )
            gazePlaneDiskOverlayController.update(
                isVisible: viewModel.isGazePlaneDiskVisible,
                diskWorldTransform: viewModel.gazePlaneDiskWorldTransform,
                statusText: viewModel.gazePlaneDiskOverlayText,
                cameraWorldPosition: viewModel.gazePlaneDiskCameraWorldPosition,
                content: content
            )
            virtualPianoOverlayController.update(
                isEnabled: viewModel.isVirtualPianoEnabled,
                keyboardGeometry: viewModel.practiceSessionViewModel.keyboardGeometry,
                content: content
            )
            virtualPerformerOverlayController.update(
                isEnabled: viewModel.isVirtualPerformerEnabled,
                isPerforming: viewModel.isAIPerformanceActive,
                keyboardGeometry: viewModel.practiceSessionViewModel.keyboardGeometry,
                cameraWorldPosition: viewModel.latestDeviceWorldPosition,
                performanceSchedule: viewModel.latestAIPerformanceSchedule,
                content: content
            )
        }
        .onAppear {
            viewModel.onImmersiveAppear()
        }
        .onDisappear {
            panoramaLoadTask?.cancel()
            panoramaLoadTask = nil
            viewModel.onImmersiveDisappear()
        }
    }
}

#Preview(immersionStyle: .progressive(0.0...1.0, initialAmount: 0.7, aspectRatio: nil)) {
    let appState = AppState()
    ImmersiveView(viewModel: ARGuideViewModel(appState: appState))
}
