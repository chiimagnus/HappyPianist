import Foundation
import Observation

@MainActor
@Observable
final class BluetoothAccessViewModel {
    var status: BluetoothAccessPreflight.Status = .unknown

    private let preflight: any BluetoothAccessPreflightProtocol
    private let settingsURLProvider: any AppSettingsURLProviderProtocol

    init(
        preflight: (any BluetoothAccessPreflightProtocol)? = nil,
        settingsURLProvider: (any AppSettingsURLProviderProtocol)? = nil
    ) {
        self.preflight = preflight ?? BluetoothAccessPreflight()
        self.settingsURLProvider = settingsURLProvider ?? AppSettingsURLProvider()
    }

    var appSettingsURL: URL? {
        settingsURLProvider.appSettingsURL
    }

    func refreshStatus() async {
        status = await preflight.checkOrRequestAccess()
    }
}
