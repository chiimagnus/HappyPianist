import Observation

@MainActor
@Observable
final class FlowState {
    var selectedPianoModeID: String?
    var isCalibrationCompleted = false
    var isVirtualPianoPlaced = false
    var bluetoothMIDISourceCount = 0

    var importedFile: ImportedMusicXMLFile?
    var importedSteps: [PracticeStep] = []
    var importErrorMessage: String?

    var onStepsImported: ((PreparedPractice) -> Void)?

    func setImportedSteps(from prepared: PreparedPractice) {
        importedSteps = prepared.steps
        importedFile = prepared.file
        importErrorMessage = nil
        onStepsImported?(prepared)
    }

    func clearSongAndSteps() {
        importedFile = nil
        importedSteps = []
        importErrorMessage = nil
    }
}
