@testable import HappyPianistAVP

extension AppState {
    @MainActor
    convenience init(
        keyGeometryService: PianoKeyGeometryServiceProtocol? = nil,
        arTrackingService: ARTrackingServiceProtocol? = nil
    ) {
        self.init(
            arTrackingService: arTrackingService ?? ARTrackingService(),
            calibrationCaptureService: CalibrationPointCaptureService(),
            calibrationRepository: CalibrationRepository(),
            keyGeometryService: keyGeometryService ?? PianoKeyGeometryService()
        )
    }
}
