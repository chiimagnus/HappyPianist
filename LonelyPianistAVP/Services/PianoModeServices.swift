enum PianoModeCatalogService {
    static func makeDefaultModes() -> [any PianoModeProtocol] {
        [
            RealAudioPianoMode(),
            BluetoothMIDIPianoMode(),
            VirtualPianoMode(),
        ]
    }
}

final class PianoModeRegistryService: PianoModeRegistryProtocol {
    let modes: [any PianoModeProtocol]

    init(modes: [any PianoModeProtocol]) {
        self.modes = modes
    }

    func mode(for id: String?) -> (any PianoModeProtocol)? {
        guard let id, id.isEmpty == false else { return nil }
        return modes.first { $0.id == id }
    }
}

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
