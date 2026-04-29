import Foundation

enum ManualAdvanceMode: String, CaseIterable, Identifiable {
    case step
    case measure

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
            case .step:
                "逐步"
            case .measure:
                "按小节"
        }
    }

    var nextButtonTitle: String {
        switch self {
            case .step:
                "下一步"
            case .measure:
                "下一节"
        }
    }

    var replayButtonTitle: String {
        switch self {
            case .step:
                "播放琴声"
            case .measure:
                "重播本节"
        }
    }

    static func storageValue(from rawValue: String?) -> ManualAdvanceMode {
        guard let rawValue else { return .step }
        return ManualAdvanceMode(rawValue: rawValue) ?? .step
    }
}
