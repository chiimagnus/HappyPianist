enum PianoModeCatalogService {
    static func makeDefaultModes() -> [any PianoModeProtocol] {
        [
            RealAudioPianoMode(),
            BluetoothMIDIPianoMode(),
            VirtualPianoMode(),
        ]
    }
}
