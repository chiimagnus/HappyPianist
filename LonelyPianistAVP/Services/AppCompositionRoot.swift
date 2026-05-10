import Foundation

@MainActor
final class AppCompositionRoot {
    let services: AppServices
    let appState: AppState
    let arGuideViewModel: ARGuideViewModel

    init() {
        let services = AppServices()
        let appState = AppState(
            arTrackingService: services.arTrackingService,
            calibrationCaptureService: services.calibrationCaptureService,
            calibrationRepository: services.calibrationRepository,
            keyGeometryService: services.keyGeometryService,
            importService: services.importService,
            practicePreparationService: services.practicePreparationService
        )
        appState.loadStoredCalibrationIfPossible()

        self.services = services
        self.appState = appState
        self.arGuideViewModel = ARGuideViewModel(appState: appState)
    }
}
