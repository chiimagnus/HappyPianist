import Foundation

enum ImprovBackendKind: String, CaseIterable, Codable, Hashable, Identifiable {
    case networkBonjourHTTP = "network_bonjour_http"
    case localRule = "local_rule"
    case tickRangeReplay = "tick_range_replay"

    var id: String {
        rawValue
    }
}
