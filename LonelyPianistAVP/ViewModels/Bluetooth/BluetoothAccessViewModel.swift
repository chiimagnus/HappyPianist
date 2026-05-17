import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class BluetoothAccessViewModel {
    var status: BluetoothAccessPreflight.Status = .unknown

    private let preflight: BluetoothAccessPreflight

    init() {
        preflight = BluetoothAccessPreflight()
    }

    init(preflight: BluetoothAccessPreflight) {
        self.preflight = preflight
    }

    func refreshStatus() async {
        status = await preflight.checkOrRequestAccess()
    }

    func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
