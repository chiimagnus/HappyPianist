struct VirtualPianoMode: PianoModeProtocol {
    let descriptor = PianoModeDescriptor(
        id: .virtualPiano,
        pickerCard: PianoModePickerCard(
            title: "虚拟钢琴",
            subtitle: "在空间中放置虚拟钢琴",
            iconSystemName: "arkit"
        ),
        preparationRoute: .virtualPiano,
        usesBluetoothMIDIInput: false,
        isVirtualPianoMode: true,
        recordingSourceText: "录制来源：虚拟钢琴触键"
    )

    func canProceedToLibrary(context: PianoModeReadinessContext) -> Bool {
        context.isVirtualPianoPlaced
    }

    func practiceTrackingMode(isVirtualPianoEnabled _: Bool) -> ARTrackingMode {
        .practiceVirtualOrAudio
    }
}

