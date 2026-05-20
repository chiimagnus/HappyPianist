extension PianoModeReadinessContext {
    init(practiceSetupState: PracticeSetupState) {
        self.init(
            isCalibrationCompleted: practiceSetupState.isCalibrationCompleted,
            isVirtualPianoPlaced: practiceSetupState.isVirtualPianoPlaced,
            bluetoothMIDISourceCount: practiceSetupState.bluetoothMIDISourceCount
        )
    }
}
