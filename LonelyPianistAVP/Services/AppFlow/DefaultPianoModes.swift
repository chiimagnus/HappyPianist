import SwiftUI

struct RealAudioPianoMode: PianoModeProtocol {
    let id = "real_audio"
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

    func makePreparationView(arGuideViewModel: ARGuideViewModel) -> AnyView {
        AnyView(RealPianoPreparationView(viewModel: arGuideViewModel))
    }

    func makePracticeSessionViewModel() -> PracticeSessionViewModel {
        makePracticeSessionViewModelClosure()
    }
}

struct BluetoothMIDIPianoMode: PianoModeProtocol {
    let id = "bluetooth_midi"
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

    func makePreparationView(arGuideViewModel: ARGuideViewModel) -> AnyView {
        AnyView(BluetoothMIDIPreparationView(viewModel: arGuideViewModel))
    }

    func makePracticeSessionViewModel() -> PracticeSessionViewModel {
        makePracticeSessionViewModelClosure()
    }
}

struct VirtualPianoMode: PianoModeProtocol {
    let id = "virtual_piano"
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

    func makePreparationView(arGuideViewModel: ARGuideViewModel) -> AnyView {
        AnyView(VirtualPianoPreparationView(viewModel: arGuideViewModel))
    }

    func makePracticeSessionViewModel() -> PracticeSessionViewModel {
        makePracticeSessionViewModelClosure()
    }
}
