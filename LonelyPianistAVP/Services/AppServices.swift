import Foundation

@MainActor
@Observable
final class AppServices {
    let worldAnchorCalibrationStore: WorldAnchorCalibrationStoreProtocol
    let keyGeometryService: PianoKeyGeometryServiceProtocol
    let importService: MusicXMLImportServiceProtocol
    let parser: MusicXMLParserProtocol
    let stepBuilder: PracticeStepBuilderProtocol
    let arTrackingService: ARTrackingServiceProtocol
    let calibrationCaptureService: CalibrationPointCaptureService

    init(
        worldAnchorCalibrationStore: WorldAnchorCalibrationStoreProtocol? = nil,
        keyGeometryService: PianoKeyGeometryServiceProtocol? = nil,
        importService: MusicXMLImportServiceProtocol? = nil,
        parser: MusicXMLParserProtocol? = nil,
        stepBuilder: PracticeStepBuilderProtocol? = nil,
        arTrackingService: ARTrackingServiceProtocol? = nil,
        calibrationCaptureService: CalibrationPointCaptureService? = nil
    ) {
        self.worldAnchorCalibrationStore = worldAnchorCalibrationStore ?? WorldAnchorCalibrationStore()
        self.keyGeometryService = keyGeometryService ?? PianoKeyGeometryService()
        self.importService = importService ?? MusicXMLImportService()
        self.parser = parser ?? MusicXMLParser()
        self.stepBuilder = stepBuilder ?? PracticeStepBuilder()
        self.arTrackingService = arTrackingService ?? ARTrackingService()
        self.calibrationCaptureService = calibrationCaptureService ?? CalibrationPointCaptureService()
    }
}
