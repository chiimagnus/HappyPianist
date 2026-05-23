struct PianoModeID: RawRepresentable, Hashable, Equatable {
    let rawValue: String

    static let realAudio = PianoModeID(rawValue: "real_audio")
    static let bluetoothMIDI = PianoModeID(rawValue: "bluetooth_midi")
    static let virtualPiano = PianoModeID(rawValue: "virtual_piano")
}

struct PianoModePickerCard: Equatable {
    let title: String
    let subtitle: String
    let iconSystemName: String
}

enum PianoModePreparationRoute: Equatable {
    case realPiano
    case bluetoothMIDI
    case virtualPiano
}

struct PianoModeReadinessContext: Equatable {
    let isCalibrationCompleted: Bool
    let isVirtualPianoPlaced: Bool
    let bluetoothMIDISourceCount: Int
}

struct PianoModeDescriptor: Equatable {
    let id: PianoModeID
    let pickerCard: PianoModePickerCard
    let preparationRoute: PianoModePreparationRoute
    let usesBluetoothMIDIInput: Bool
    let isVirtualPianoMode: Bool
    let recordingSourceText: String?
}

protocol PianoModeProtocol {
    var descriptor: PianoModeDescriptor { get }
    func canProceedToLibrary(context: PianoModeReadinessContext) -> Bool
    func practiceTrackingMode(isVirtualPianoEnabled: Bool) -> ARTrackingMode
}

extension PianoModeProtocol {
    var id: String {
        descriptor.id.rawValue
    }

    var pickerCard: PianoModePickerCard {
        descriptor.pickerCard
    }

    var preparationRoute: PianoModePreparationRoute {
        descriptor.preparationRoute
    }

    var usesBluetoothMIDIInput: Bool {
        descriptor.usesBluetoothMIDIInput
    }

    var isVirtualPianoMode: Bool {
        descriptor.isVirtualPianoMode
    }

    func recordingSourceText() -> String? {
        descriptor.recordingSourceText
    }
}

protocol PianoModeRegistryProtocol {
    var modes: [any PianoModeProtocol] { get }
    func mode(for id: String?) -> (any PianoModeProtocol)?
}
