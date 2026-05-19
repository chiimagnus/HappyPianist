import Foundation

final class PracticeSessionViewModelFactoryService: PracticeSessionViewModelFactoryProtocol {
    private let pianoModeRegistry: PianoModeRegistryProtocol
    private let makeFallbackPracticeSessionViewModel: @MainActor () -> PracticeSessionViewModel

    init(
        pianoModeRegistry: PianoModeRegistryProtocol,
        makeFallbackPracticeSessionViewModel: @escaping @MainActor () -> PracticeSessionViewModel
    ) {
        self.pianoModeRegistry = pianoModeRegistry
        self.makeFallbackPracticeSessionViewModel = makeFallbackPracticeSessionViewModel
    }

    func makePracticeSessionViewModel(for pianoModeID: String?) -> PracticeSessionViewModel {
        guard let mode = pianoModeRegistry.mode(for: pianoModeID) else {
            return makeFallbackPracticeSessionViewModel()
        }
        return mode.makePracticeSessionViewModel()
    }
}
