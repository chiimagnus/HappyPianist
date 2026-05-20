struct PianoModeDescriptor: Equatable {
    let id: PianoModeID
    let pickerCard: PianoModePickerCard
    let preparationRoute: PianoModePreparationRoute
    let usesBluetoothMIDIInput: Bool
    let isVirtualPianoMode: Bool
    let recordingSourceText: String?
}
