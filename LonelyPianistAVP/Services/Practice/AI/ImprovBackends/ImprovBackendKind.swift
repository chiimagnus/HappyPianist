import Foundation

enum ImprovBackendKind: String, CaseIterable, Codable, Hashable, Identifiable {
    case networkBonjourHTTPAriaV2 = "network_bonjour_http_aria_v2"
    case networkBonjourWebSocketAriaV2 = "network_bonjour_ws_aria_v2"
    case localCoreMLDuet = "local_coreml_duet"
    case localRule = "local_rule"
    case tickRangeReplay = "tick_range_replay"

    var id: String {
        rawValue
    }
}
