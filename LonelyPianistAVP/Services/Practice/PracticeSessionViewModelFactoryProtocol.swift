import Foundation

protocol PracticeSessionViewModelFactoryProtocol: AnyObject {
    @MainActor
    func makePracticeSessionViewModel(for pianoKind: PianoKind?) -> PracticeSessionViewModel
}
