import AppKit
import ApplicationServices
import Foundation

struct AccessibilityPermissionService: PermissionServiceProtocol {
    func hasAccessibilityPermission() -> Bool {
        AXIsProcessTrusted() || CGPreflightPostEventAccess()
    }

    func requestAccessibilityPermission() -> Bool {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: kCFBooleanTrue as Any,
        ] as CFDictionary
        let axGranted = AXIsProcessTrustedWithOptions(options)
        let cgGranted = CGRequestPostEventAccess()
        return axGranted || cgGranted
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
