import Foundation

final class PracticeSessionViewModelFactoryService: PracticeSessionViewModelFactoryProtocol {
    private let pianoModeRegistry: PianoModeRegistryProtocol

    init(pianoModeRegistry: PianoModeRegistryProtocol = PianoModeRegistryService()) {
        self.pianoModeRegistry = pianoModeRegistry
    }

    func makePracticeSessionViewModel(for pianoModeID: String?) -> PracticeSessionViewModel {
        guard let mode = pianoModeRegistry.mode(for: pianoModeID) else {
            return PracticeSessionViewModel()
        }
        return mode.makePracticeSessionViewModel()
    }
}
