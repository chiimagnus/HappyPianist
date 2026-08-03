import SwiftUI

@main
struct HappyPianistMacApp: App {
    private let graph: MacAppGraph

    init() {
        graph = .make()
    }

    var body: some Scene {
        WindowGroup("HappyPianist") {
            ContentUnavailableView {
                Label("导入 MusicXML", systemImage: "music.note.list")
            } description: {
                Text(graph.libraryEntryState.message)
            }
        }
    }
}
