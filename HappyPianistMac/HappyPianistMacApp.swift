import SwiftUI

@main
struct HappyPianistMacApp: App {
    @NSApplicationDelegateAdaptor(MacApplicationTerminationDelegate.self)
    private var terminationDelegate
    private let graph: MacAppGraph

    init() {
        graph = .make()
        terminationDelegate.finishPractice = { [practiceViewModel = graph.practiceViewModel] in
            guard practiceViewModel.state != .idle else { return true }
            return await practiceViewModel.returnToLibrary()
        }
    }

    var body: some Scene {
        WindowGroup("HappyPianist") {
            MacLibraryRootView(
                viewModel: graph.songLibraryViewModel,
                midiSettingsViewModel: graph.midiSettingsViewModel,
                diagnosticsViewModel: graph.diagnosticsViewModel,
                practiceViewModel: graph.practiceViewModel
            )
        }
    }
}
