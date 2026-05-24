import Foundation

enum ImprovBackendKind: String, CaseIterable, Codable, Hashable, Identifiable {
    case networkBonjourHTTPDuet = "network_bonjour_http_duet"
    case localCoreMLDuet = "local_coreml_duet"
    case localRule = "local_rule"
    case tickRangeReplay = "tick_range_replay"

    var id: String {
        rawValue
    }
}
