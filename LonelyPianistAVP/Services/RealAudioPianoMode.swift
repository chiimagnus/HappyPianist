struct RealAudioPianoMode: PianoModeProtocol {
    let descriptor = PianoModeDescriptor(
        id: .realAudio,
        pickerCard: PianoModePickerCard(
            title: "真实钢琴（音频）",
            subtitle: "通过麦克风识别弹奏",
            iconSystemName: "pianokeys"
        ),
        preparationRoute: .realPiano,
        usesBluetoothMIDIInput: false,
        isVirtualPianoMode: false,
        recordingSourceText: "录制来源：手势触键（用于推断按键接触）"
    )

    func canProceedToLibrary(context: PianoModeReadinessContext) -> Bool {
        context.isCalibrationCompleted
    }

    func practiceTrackingMode(isVirtualPianoEnabled _: Bool) -> ARTrackingMode {
        .practiceVirtualOrAudio
    }
}

