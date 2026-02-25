import Foundation

@MainActor
final class AppContext {
    static let shared = AppContext()

    var viewModel: PianoKeyViewModel?
}

