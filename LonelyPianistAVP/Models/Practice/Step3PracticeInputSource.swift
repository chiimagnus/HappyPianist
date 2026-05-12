import Foundation

enum Step3PracticeInputSource: String, CaseIterable, Identifiable {
    case audio
    case bluetoothMIDI

    var id: String { rawValue }

    var title: String {
        switch self {
            case .audio:
                "音频识别"
            case .bluetoothMIDI:
                "Bluetooth MIDI"
        }
    }
}

