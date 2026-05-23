import AppKit
import CoreAudioKit
import Foundation
import Observation

@MainActor
@Observable
final class BluetoothMIDIViewModel {
    enum PrimaryAction: Equatable {
        case openPrivacySettings
        case openBluetoothSettings
        case ok
    }

    struct AlertInfo: Identifiable, Equatable {
        enum Kind: Equatable {
            case unauthorized
            case bluetoothOff
            case unsupported
            case unknown
        }

        let id = UUID()
        let kind: Kind

        var title: String {
            switch kind {
            case .unauthorized:
                "Bluetooth Permission Needed"
            case .bluetoothOff:
                "Bluetooth Is Off"
            case .unsupported:
                "Bluetooth Not Supported"
            case .unknown:
                "Bluetooth Unavailable"
            }
        }

        var message: String {
            switch kind {
            case .unauthorized:
                "请在 System Settings → Privacy & Security → Bluetooth 中允许 LonelyPianist 访问蓝牙，然后再重试。"
            case .bluetoothOff:
                "请先在系统中打开蓝牙，然后再连接 Bluetooth MIDI。"
            case .unsupported:
                "当前设备不支持蓝牙，无法使用 Bluetooth MIDI。"
            case .unknown:
                "系统蓝牙状态暂不可用。请稍后重试，或重启蓝牙后再试。"
            }
        }

        var primaryButtonTitle: String {
            switch kind {
            case .unauthorized:
                "Open Settings"
            case .bluetoothOff:
                "Open Bluetooth Settings"
            case .unsupported, .unknown:
                "OK"
            }
        }

        var primaryAction: PrimaryAction {
            switch kind {
            case .unauthorized:
                .openPrivacySettings
            case .bluetoothOff:
                .openBluetoothSettings
            case .unsupported, .unknown:
                .ok
            }
        }
    }

    var alert: AlertInfo?

    private var windowController: CABTLEMIDIWindowController?
    private let preflight: BluetoothAccessPreflight

    init() {
        preflight = BluetoothAccessPreflight()
    }

    init(preflight: BluetoothAccessPreflight) {
        self.preflight = preflight
    }

    func openBluetoothMIDIWindow() async {
        let status = await preflight.checkOrRequestAccess()
        switch status {
        case .ready:
            showBluetoothMIDIWindow()
        case .bluetoothPoweredOff:
            alert = AlertInfo(kind: .bluetoothOff)
        case .unauthorized:
            alert = AlertInfo(kind: .unauthorized)
        case .unsupported:
            alert = AlertInfo(kind: .unsupported)
        case .unknown:
            alert = AlertInfo(kind: .unknown)
        }
    }

    func dismissAlert() {
        alert = nil
    }

    func performPrimaryAction(_ action: PrimaryAction) {
        switch action {
        case .openPrivacySettings:
            openBluetoothPrivacySettings()
        case .openBluetoothSettings:
            openBluetoothSettings()
        case .ok:
            break
        }
    }

    private func showBluetoothMIDIWindow() {
        let controller = windowController ?? CABTLEMIDIWindowController()
        windowController = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    private func openBluetoothPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth")
        else { return }
        NSWorkspace.shared.open(url)
    }

    private func openBluetoothSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Bluetooth") {
            NSWorkspace.shared.open(url)
        } else if let url = URL(string: "x-apple.systempreferences:") {
            NSWorkspace.shared.open(url)
        }
    }
}
