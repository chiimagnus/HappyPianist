struct RealAudioPianoMode: PianoModeProtocol {
    let id = "real_audio"
    let preparationRoute: PianoModePreparationRoute = .realPiano
    private let makePracticeSessionViewModelClosure: @MainActor () -> PracticeSessionViewModel

    let pickerCard = PianoModePickerCard(
        title: "真实钢琴（音频）",
        subtitle: "通过麦克风识别弹奏",
        iconSystemName: "pianokeys"
    )

    let usesBluetoothMIDIInput = false
    let isVirtualPianoMode = false

    init(makePracticeSessionViewModel: @escaping @MainActor () -> PracticeSessionViewModel) {
        makePracticeSessionViewModelClosure = makePracticeSessionViewModel
    }

    func canProceedToLibrary(flowState: FlowState) -> Bool {
        flowState.isCalibrationCompleted
    }

    func practiceTrackingMode(isVirtualPianoEnabled _: Bool) -> ARTrackingMode {
        .practiceVirtualOrAudio
    }

    func recordingSourceText() -> String? {
        "录制来源：手势触键（用于推断按键接触）"
    }

    func makePracticeSessionViewModel() -> PracticeSessionViewModel {
        makePracticeSessionViewModelClosure()
    }
}

struct BluetoothMIDIPianoMode: PianoModeProtocol {
    let id = "bluetooth_midi"
    let preparationRoute: PianoModePreparationRoute = .bluetoothMIDI
    private let makePracticeSessionViewModelClosure: @MainActor () -> PracticeSessionViewModel

    let pickerCard = PianoModePickerCard(
        title: "真实钢琴（蓝牙 MIDI）",
        subtitle: "通过系统 Bluetooth MIDI 连接",
        iconSystemName: "dot.radiowaves.left.and.right"
    )

    let usesBluetoothMIDIInput = true
    let isVirtualPianoMode = false

    init(makePracticeSessionViewModel: @escaping @MainActor () -> PracticeSessionViewModel) {
        makePracticeSessionViewModelClosure = makePracticeSessionViewModel
    }

    func canProceedToLibrary(flowState: FlowState) -> Bool {
        flowState.isCalibrationCompleted && flowState.bluetoothMIDISourceCount > 0
    }

    func practiceTrackingMode(isVirtualPianoEnabled: Bool) -> ARTrackingMode {
        usesBluetoothMIDIInput && isVirtualPianoEnabled == false ? .practiceBluetoothMIDI : .practiceVirtualOrAudio
    }

    func recordingSourceText() -> String? {
        "录制来源：Bluetooth MIDI（弹奏琴键即可录制）"
    }

    func makePracticeSessionViewModel() -> PracticeSessionViewModel {
        makePracticeSessionViewModelClosure()
    }
}

struct VirtualPianoMode: PianoModeProtocol {
    let id = "virtual_piano"
    let preparationRoute: PianoModePreparationRoute = .virtualPiano
    private let makePracticeSessionViewModelClosure: @MainActor () -> PracticeSessionViewModel

    let pickerCard = PianoModePickerCard(
        title: "虚拟钢琴",
        subtitle: "在空间中放置虚拟钢琴",
        iconSystemName: "arkit"
    )

    let usesBluetoothMIDIInput = false
    let isVirtualPianoMode = true

    init(makePracticeSessionViewModel: @escaping @MainActor () -> PracticeSessionViewModel) {
        makePracticeSessionViewModelClosure = makePracticeSessionViewModel
    }

    func canProceedToLibrary(flowState: FlowState) -> Bool {
        flowState.isVirtualPianoPlaced
    }

    func practiceTrackingMode(isVirtualPianoEnabled _: Bool) -> ARTrackingMode {
        .practiceVirtualOrAudio
    }

    func recordingSourceText() -> String? {
        "录制来源：虚拟钢琴触键"
    }

    func makePracticeSessionViewModel() -> PracticeSessionViewModel {
        makePracticeSessionViewModelClosure()
    }
}
