import Foundation
import UIKit

protocol AppSettingsURLProviderProtocol {
    var appSettingsURL: URL? { get }
}

struct AppSettingsURLProvider: AppSettingsURLProviderProtocol {
    var appSettingsURL: URL? {
        URL(string: UIApplication.openSettingsURLString)
    }
}
