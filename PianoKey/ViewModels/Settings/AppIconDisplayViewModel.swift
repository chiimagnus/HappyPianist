import AppKit
import MenuBarDockKit
import Observation

@MainActor
@Observable
final class AppIconDisplayViewModel {
    var selectedMode: AppIconDisplayMode {
        didSet {
            guard selectedMode != oldValue else { return }
            applyDisplayMode(selectedMode)
        }
    }

    init() {
        self.selectedMode = AppIconDisplayMode.current
    }

    func applyDisplayMode(_ mode: AppIconDisplayMode) {
        AppIconDisplayMode.current = mode
        updateActivationPolicy(for: mode)

        NotificationCenter.default.post(
            name: .appIconDisplayModeChanged,
            object: mode
        )
    }

    static func applyStoredMode() {
        let mode = AppIconDisplayMode.current
        updateActivationPolicyStatic(for: mode)
    }

    private func updateActivationPolicy(for mode: AppIconDisplayMode) {
        Self.updateActivationPolicyStatic(for: mode)
    }

    private static func updateActivationPolicyStatic(for mode: AppIconDisplayMode) {
        let app = NSApplication.shared

        let currentPolicy = app.activationPolicy()
        let newPolicy: NSApplication.ActivationPolicy

        switch mode {
        case .menuBarOnly:
            newPolicy = .accessory
        case .dockOnly, .both:
            newPolicy = .regular
        }

        guard currentPolicy != newPolicy else { return }

        app.setActivationPolicy(newPolicy)

        if currentPolicy == .accessory && newPolicy == .regular {
            app.activate(ignoringOtherApps: true)
        }
    }
}

