protocol PianoModeProtocol {
    var descriptor: PianoModeDescriptor { get }
    func canProceedToLibrary(context: PianoModeReadinessContext) -> Bool
    func practiceTrackingMode(isVirtualPianoEnabled: Bool) -> ARTrackingMode
}

extension PianoModeProtocol {
    var id: String { descriptor.id.rawValue }
    var pickerCard: PianoModePickerCard { descriptor.pickerCard }
    var preparationRoute: PianoModePreparationRoute { descriptor.preparationRoute }
    var usesBluetoothMIDIInput: Bool { descriptor.usesBluetoothMIDIInput }
    var isVirtualPianoMode: Bool { descriptor.isVirtualPianoMode }

    func recordingSourceText() -> String? {
        descriptor.recordingSourceText
    }
}
