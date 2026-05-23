enum ARTrackingMode: Equatable {
    case calibration
    case practiceBluetoothMIDI
    case practiceVirtualOrAudio
}

enum DataProviderState: Equatable {
    case idle
    case running
    case unsupported
    case unauthorized
    case disabled
    case stopped
    case failed(reason: String)

    var description: String {
        switch self {
        case .idle:
            "idle"
        case .running:
            "running"
        case .unsupported:
            "unsupported"
        case .unauthorized:
            "unauthorized"
        case .disabled:
            "disabled"
        case .stopped:
            "stopped"
        case let .failed(reason):
            "failed(\(reason))"
        }
    }
}
