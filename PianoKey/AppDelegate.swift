import AppKit
import MenuBarDockKit
import SwiftUI

@MainActor
@objc final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Apply stored icon display mode (NSApp is ready at this point).
        AppIconDisplayViewModel.applyStoredMode()
    }

    // Prevent AppKit from creating an untitled new window when app is activated.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
    }

    /// When the last window closed:
    /// - `.menuBarOnly`: hide Dock (the app stays available via the menu bar icon).
    /// - Other modes: keep Dock visible.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        DispatchQueue.main.async {
            Task { @MainActor in
                DockPresenceService.hideDockIfAllowedWhenNoVisibleWindows()
            }
        }
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let mainWindow = sender.windows.first(where: { $0.identifier?.rawValue == "main" }) {
            mainWindow.makeKeyAndOrderFront(nil)
            sender.activate(ignoringOtherApps: true)
            return true
        }

        if let anyWindow = sender.windows.first {
            anyWindow.makeKeyAndOrderFront(nil)
            sender.activate(ignoringOtherApps: true)
        }
        return true
    }
}
