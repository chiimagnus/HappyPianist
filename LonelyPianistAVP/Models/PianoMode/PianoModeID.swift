struct PianoModeID: RawRepresentable, Hashable, Equatable {
    let rawValue: String

    static let realAudio = PianoModeID(rawValue: "real_audio")
    static let bluetoothMIDI = PianoModeID(rawValue: "bluetooth_midi")
    static let virtualPiano = PianoModeID(rawValue: "virtual_piano")
}
