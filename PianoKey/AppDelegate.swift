import AppKit
import MenuBarDockKit
import SwiftUI

@MainActor
@objc final class AppDelegate: NSObject, NSApplicationDelegate {
    private var iconModeObserver: NSObjectProtocol?
    private var menuBarPopoverController: MenuBarPopoverController?

    deinit {
        if let token = iconModeObserver {
            NotificationCenter.default.removeObserver(token)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Apply stored icon display mode (NSApp is ready at this point).
        AppIconDisplayViewModel.applyStoredMode()

        let controller = MenuBarPopoverController(
            systemSymbolName: "pianokeys",
            contentSize: NSSize(width: 320, height: 420)
        ) {
            if let viewModel = AppContext.shared.viewModel {
                MenuBarPanelView(viewModel: viewModel)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("PianoKey")
                        .font(.headline)
                    Text("Launching…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(width: 320, alignment: .leading)
            }
        }

        controller.setVisible(AppIconDisplayMode.current.showsMenuBarIcon)
        menuBarPopoverController = controller

        iconModeObserver = NotificationCenter.default.addObserver(
            forName: .appIconDisplayModeChanged,
            object: nil,
            queue: .main
        ) { [weak self] n in
            let mode = (n.object as? AppIconDisplayMode) ?? AppIconDisplayMode.current
            Task { @MainActor in
                self?.menuBarPopoverController?.setVisible(mode.showsMenuBarIcon)
            }
        }
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

