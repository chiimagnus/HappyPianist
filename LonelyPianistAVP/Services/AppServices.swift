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
    let practicePreparationService: PracticePreparationServiceProtocol

    init(
        worldAnchorCalibrationStore: WorldAnchorCalibrationStoreProtocol? = nil,
        keyGeometryService: PianoKeyGeometryServiceProtocol? = nil,
        importService: MusicXMLImportServiceProtocol? = nil,
        parser: MusicXMLParserProtocol? = nil,
        stepBuilder: PracticeStepBuilderProtocol? = nil,
        arTrackingService: ARTrackingServiceProtocol? = nil,
        calibrationCaptureService: CalibrationPointCaptureService? = nil,
        practicePreparationService: PracticePreparationServiceProtocol? = nil
    ) {
        self.worldAnchorCalibrationStore = worldAnchorCalibrationStore ?? WorldAnchorCalibrationStore()
        self.keyGeometryService = keyGeometryService ?? PianoKeyGeometryService()
        self.importService = importService ?? MusicXMLImportService()
        self.parser = parser ?? MusicXMLParser()
        self.stepBuilder = stepBuilder ?? PracticeStepBuilder()
        self.arTrackingService = arTrackingService ?? ARTrackingService()
        self.calibrationCaptureService = calibrationCaptureService ?? CalibrationPointCaptureService()
        self.practicePreparationService = practicePreparationService
            ?? PracticePreparationService(parser: self.parser, stepBuilder: self.stepBuilder)
    }
}
