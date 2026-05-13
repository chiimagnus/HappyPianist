final class PianoModeRegistryService: PianoModeRegistryProtocol {
    let modes: [any PianoModeProtocol]

    init(modes: [any PianoModeProtocol] = [
        RealAudioPianoMode(),
        BluetoothMIDIPianoMode(),
        VirtualPianoMode(),
    ]) {
        self.modes = modes
    }

    func mode(for id: String?) -> (any PianoModeProtocol)? {
        guard let id, id.isEmpty == false else { return nil }
        return modes.first { $0.id == id }
    }
}
