import SwiftUI

/// Maintains app-wide state
@MainActor
@Observable
class AppModel {
    let immersiveSpaceID = "ImmersiveSpace"
    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }
    var immersiveSpaceState = ImmersiveSpaceState.closed

    var practiceSessionViewModel = PracticeSessionViewModel()
    var handTrackingService = HandTrackingService()

    var importedFile: ImportedMusicXMLFile?
    var importedSteps: [PracticeStep] = []
    var importErrorMessage: String?

    var calibration: PianoCalibration? {
        didSet { applySessionIfPossible() }
    }
    var calibrationCaptureService = CalibrationPointCaptureService()
    var pendingCalibrationCaptureAnchor: CalibrationAnchorPoint?
    var calibrationStatusMessage: String?

    private let calibrationStore: PianoCalibrationStoreProtocol
    private let keyGeometryService: PianoKeyGeometryServiceProtocol
    private let importService: MusicXMLImportServiceProtocol
    private let parser: MusicXMLParserProtocol
    private let stepBuilder: PracticeStepBuilderProtocol

    init(
        calibrationStore: PianoCalibrationStoreProtocol? = nil,
        keyGeometryService: PianoKeyGeometryServiceProtocol? = nil,
        importService: MusicXMLImportServiceProtocol? = nil,
        parser: MusicXMLParserProtocol? = nil,
        stepBuilder: PracticeStepBuilderProtocol? = nil
    ) {
        self.calibrationStore = calibrationStore ?? PianoCalibrationStore()
        self.keyGeometryService = keyGeometryService ?? PianoKeyGeometryService()
        self.importService = importService ?? MusicXMLImportService()
        self.parser = parser ?? MusicXMLParser()
        self.stepBuilder = stepBuilder ?? PracticeStepBuilder()
    }

    func beginNewARGuideSession() {
        pendingCalibrationCaptureAnchor = nil
        calibrationStatusMessage = "请重新校准"
        calibration = nil
        calibrationCaptureService.reset()
        practiceSessionViewModel.resetSession()
    }

    func setImportedSteps(_ steps: [PracticeStep], file: ImportedMusicXMLFile?) {
        importedSteps = steps
        importedFile = file
        importErrorMessage = nil
        applySessionIfPossible()
    }

    func importMusicXML(from selectedURL: URL) {
        do {
            let importedFile = try importService.importFile(from: selectedURL)
            let score = try parser.parse(fileURL: importedFile.storedURL)
            let buildResult = stepBuilder.buildSteps(from: score)
            if buildResult.unsupportedNoteCount > 0 {
                importErrorMessage = "已导入（忽略了 \(buildResult.unsupportedNoteCount) 个不支持的音符）。"
            } else {
                importErrorMessage = nil
            }
            setImportedSteps(buildResult.steps, file: importedFile)
        } catch {
            importErrorMessage = "导入失败：\(error.localizedDescription)"
        }
    }

    func loadStoredCalibrationIfPossible() {
        do {
            guard let stored = try calibrationStore.load() else { return }
            calibration = stored
            calibrationCaptureService.a0Point = stored.a0.simdValue
            calibrationCaptureService.c8Point = stored.c8.simdValue
            calibrationCaptureService.updateReticleEstimate(stored.a0.simdValue)
            calibrationStatusMessage = "已加载校准"
        } catch {
            calibrationStatusMessage = "加载校准失败：\(error.localizedDescription)"
        }
    }

    func saveCalibrationIfPossible() {
        guard let built = calibrationCaptureService.buildCalibration() else {
            calibrationStatusMessage = "校准信息不完整"
            return
        }
        do {
            try calibrationStore.save(built)
            calibration = built
            calibrationStatusMessage = "已保存校准"
        } catch {
            calibrationStatusMessage = "保存校准失败：\(error.localizedDescription)"
        }
    }

    private func applySessionIfPossible() {
        guard let calibration, importedSteps.isEmpty == false else { return }
        let keyRegions = keyGeometryService.generateKeyRegions(from: calibration)
        practiceSessionViewModel.configure(steps: importedSteps, calibration: calibration, keyRegions: keyRegions)
    }
}
