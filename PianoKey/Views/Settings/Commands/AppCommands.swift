import MenuBarDockKit
import SwiftUI

struct AppCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings", systemImage: "gear") {
                AppContext.shared.viewModel?.selectedMainWindowSection = .settings
                DockPresenceService.prepareForPresentingMainWindow()
                openWindow(id: "main")
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}
