protocol PianoModeRegistryProtocol {
    var modes: [any PianoModeProtocol] { get }
    func mode(for id: String?) -> (any PianoModeProtocol)?
}
