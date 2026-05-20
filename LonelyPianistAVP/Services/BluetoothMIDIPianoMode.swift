struct BluetoothMIDIPianoMode: PianoModeProtocol {
    let descriptor = PianoModeDescriptor(
        id: .bluetoothMIDI,
        pickerCard: PianoModePickerCard(
            title: "真实钢琴（蓝牙 MIDI）",
            subtitle: "通过系统 Bluetooth MIDI 连接",
            iconSystemName: "dot.radiowaves.left.and.right"
        ),
        preparationRoute: .bluetoothMIDI,
        usesBluetoothMIDIInput: true,
        isVirtualPianoMode: false,
        recordingSourceText: "录制来源：Bluetooth MIDI（弹奏琴键即可录制）"
    )

    func canProceedToLibrary(context: PianoModeReadinessContext) -> Bool {
        context.isCalibrationCompleted && context.bluetoothMIDISourceCount > 0
    }

    func practiceTrackingMode(isVirtualPianoEnabled: Bool) -> ARTrackingMode {
        usesBluetoothMIDIInput && isVirtualPianoEnabled == false ? .practiceBluetoothMIDI : .practiceVirtualOrAudio
    }
}

