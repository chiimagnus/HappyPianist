import Observation

@MainActor
@Observable
final class PracticeSetupState {
    var selectedPianoModeID: String?
    var isCalibrationCompleted = false
    var isVirtualPianoPlaced = false
    var bluetoothMIDISourceCount = 0

    var importedFile: ImportedMusicXMLFile?
    var preparedPracticeIdentity: PracticeSongIdentity?
    var importedSteps: [PracticeStep] = []
    var importErrorMessage: String?

    func setImportedSteps(from prepared: PreparedPractice) {
        importedSteps = prepared.steps
        importedFile = prepared.file
        preparedPracticeIdentity = prepared.identity
        importErrorMessage = nil
    }

    func clearSongAndSteps() {
        importedFile = nil
        preparedPracticeIdentity = nil
        importedSteps = []
        importErrorMessage = nil
    }
}
