import MenuBarDockKit
import SwiftUI

struct AppCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings", systemImage: "gear") {
                DockPresenceService.prepareForPresentingMainWindow()
                openWindow(id: "setting")
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}

