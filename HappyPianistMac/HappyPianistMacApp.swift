import SwiftUI

@main
struct HappyPianistMacApp: App {
    private let graph: MacAppGraph

    init() {
        graph = .make()
    }

    var body: some Scene {
        WindowGroup("HappyPianist") {
            MacLibraryRootView(viewModel: graph.songLibraryViewModel)
        }
    }
}
