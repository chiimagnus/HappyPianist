enum PianoModeCatalogService {
    static func makeDefaultModes() -> [any PianoModeProtocol] {
        [
            RealAudioPianoMode(),
            BluetoothMIDIPianoMode(),
            VirtualPianoMode(),
        ]
    }
}

enum PianoModeTouchCalibrationService {
    static func conservativeDefault(for modeID: PianoModeID?) -> PianoTouchCalibration {
        switch modeID {
        case .virtualPiano:
            PianoTouchCalibration(
                planeOffsetMeters: 0.002,
                releaseHysteresisMeters: 0.006,
                minimumStrikeSpeedMetersPerSecond: 0.08,
                fullScaleStrikeSpeedMetersPerSecond: 1.2,
                minimumVelocity: 28,
                maximumVelocity: 118,
                curveExponent: 0.7,
                retriggerDebounceSeconds: 0.03
            )
        default:
            PianoTouchCalibration(
                planeOffsetMeters: 0.004,
                releaseHysteresisMeters: 0.012,
                minimumStrikeSpeedMetersPerSecond: 0.1,
                fullScaleStrikeSpeedMetersPerSecond: 1.5,
                minimumVelocity: 32,
                maximumVelocity: 112,
                curveExponent: 0.75,
                retriggerDebounceSeconds: 0.03
            )
        }
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

    func isSetupReady(context: PianoModeReadinessContext) -> Bool {
        context.isCalibrationCompleted && context.bluetoothMIDISourceCount > 0
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

    func isSetupReady(context: PianoModeReadinessContext) -> Bool {
        context.isCalibrationCompleted
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

    func isSetupReady(context: PianoModeReadinessContext) -> Bool {
        context.isVirtualPianoPlaced
    }
}
