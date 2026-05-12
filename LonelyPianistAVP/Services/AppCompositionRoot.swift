import Foundation

@MainActor
final class AppCompositionRoot {
    let services: AppServices
    let appState: AppState
    let arGuideViewModel: ARGuideViewModel
    let flowState: FlowState
    let router: AppRouter

    init() {
        let services = AppServices()
        let appState = AppState(
            arTrackingService: services.arTrackingService,
            calibrationCaptureService: services.calibrationCaptureService,
            calibrationRepository: services.calibrationRepository,
            keyGeometryService: services.keyGeometryService
        )
        appState.loadStoredCalibrationIfPossible()

        let flowState = FlowState()
        let router = AppRouter(flowState: flowState)

        self.services = services
        self.appState = appState
        self.arGuideViewModel = ARGuideViewModel(
            appState: appState,
            flowState: flowState,
            practiceSessionViewModelFactory: services.practiceSessionViewModelFactory
        )
        self.flowState = flowState
        self.router = router
    }
}
