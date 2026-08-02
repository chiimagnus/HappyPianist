import Foundation

enum PianoGuideHighlightPhase: String, Equatable, Hashable {
    case active
    case triggered
}

enum ManualAdvanceMode: String, CaseIterable, Identifiable, Codable, Equatable {
    case step
    case measure

    var id: String { rawValue }

    var title: String {
        self == .step ? "逐步" : "按小节"
    }

    var nextButtonTitle: String {
        self == .step ? "下一步" : "下一节"
    }

    var replayButtonTitle: String {
        self == .step ? "播放琴声" : "重播本节"
    }

    static func storageValue(from rawValue: String?) -> ManualAdvanceMode {
        guard let rawValue else { return .step }
        return ManualAdvanceMode(rawValue: rawValue) ?? .step
    }
}
