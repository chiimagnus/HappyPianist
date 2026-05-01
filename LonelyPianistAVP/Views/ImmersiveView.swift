import RealityKit
import SwiftUI

struct ImmersiveView: View {
    @Bindable var viewModel: ARGuideViewModel
    @State private var overlayController = PianoGuideOverlayController()
    @State private var calibrationOverlayController = CalibrationOverlayController()
    @State private var keyboardAxesDebugOverlayController = KeyboardAxesDebugOverlayController()
    @State private var virtualPianoOverlayController = VirtualPianoOverlayController()
    @AppStorage("debugKeyboardAxesOverlayEnabled") private var debugKeyboardAxesOverlayEnabled = false
    @State private var panoramaBackgroundEntity: ModelEntity?

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
                content.add(entity)
                panoramaBackgroundEntity = entity

                Task {
                    let texture = try? await TextureResource(named: "full-immersive1.jpg", in: .main)
                    guard let texture else { return }

                    var texturedMaterial = UnlitMaterial()
                    texturedMaterial.color = .init(tint: UIColor.white, texture: .init(texture))
                    texturedMaterial.faceCulling = .front

                    await MainActor.run {
                        panoramaBackgroundEntity?.model?.materials = [texturedMaterial]
                    }
                }
            }

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
            virtualPianoOverlayController.update(
                placementState: viewModel.virtualPianoTablePlacement.state,
                keyboardGeometry: viewModel.practiceSessionViewModel.keyboardGeometry,
                content: content
            )
            if viewModel.isVirtualPianoEnabled {
                viewModel.syncVirtualPianoTableWorldFromAnchor(
                    virtualPianoOverlayController.currentTableWorldFromAnchor()
                )
            }
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
                keyboardFrame: viewModel.practiceSessionViewModel.calibration?.keyboardFrame,
                content: content
            )
            overlayController.updateHighlights(
                highlightGuide: viewModel.practiceSessionViewModel.currentPianoHighlightGuide,
                keyboardGeometry: viewModel.practiceSessionViewModel.keyboardGeometry,
                content: content
            )
            virtualPianoOverlayController.update(
                placementState: viewModel.virtualPianoTablePlacement.state,
                keyboardGeometry: viewModel.practiceSessionViewModel.keyboardGeometry,
                content: content
            )
            if viewModel.isVirtualPianoEnabled {
                viewModel.syncVirtualPianoTableWorldFromAnchor(
                    virtualPianoOverlayController.currentTableWorldFromAnchor()
                )
            }
        }
        .onAppear {
            viewModel.onImmersiveAppear()
        }
        .onDisappear {
            viewModel.onImmersiveDisappear()
        }
        .onChange(of: viewModel.virtualPianoTablePlacement.state) {
            virtualPianoOverlayController.update(
                placementState: viewModel.virtualPianoTablePlacement.state,
                keyboardGeometry: viewModel.practiceSessionViewModel.keyboardGeometry,
                content: nil
            )
        }
        .onChange(of: viewModel.practiceSessionViewModel.keyboardGeometry) {
            virtualPianoOverlayController.update(
                placementState: viewModel.virtualPianoTablePlacement.state,
                keyboardGeometry: viewModel.practiceSessionViewModel.keyboardGeometry,
                content: nil
            )
        }
    }
}

#Preview(immersionStyle: .mixed) {
    let appState = AppState()
    ImmersiveView(viewModel: ARGuideViewModel(appState: appState))
}
