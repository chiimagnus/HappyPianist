struct PianoModePickerCard: Equatable {
    let title: String
    let subtitle: String
    let iconSystemName: String
}

protocol PianoModeProtocol {
    var id: String { get }
    var pickerCard: PianoModePickerCard { get }
    var preparationRoute: PianoModePreparationRoute { get }

    var usesBluetoothMIDIInput: Bool { get }
    var isVirtualPianoMode: Bool { get }

    @MainActor
    func canProceedToLibrary(flowState: FlowState) -> Bool
    @MainActor
    func practiceTrackingMode(isVirtualPianoEnabled: Bool) -> ARTrackingMode
    @MainActor
    func recordingSourceText() -> String?

    @MainActor
    func makePracticeSessionViewModel() -> PracticeSessionViewModel
}
