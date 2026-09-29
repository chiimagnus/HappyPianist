import Foundation

enum ImprovBackendKind: String, CaseIterable, Codable, Hashable, Identifiable {
    case networkBonjourHTTPAria = "network_bonjour_http_aria"
    case localCoreMLDuet = "local_coreml_duet"
    case localRule = "local_rule"

    var id: String {
        rawValue
    }
}
