import Foundation

protocol PracticeSessionViewModelFactoryProtocol: AnyObject {
    @MainActor
    func makePracticeSessionViewModel(for pianoModeID: String?) -> PracticeSessionViewModel
}
