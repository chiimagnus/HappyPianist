import MusicXML

public struct GrandStaffNotationMeasureAnnotation: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case stable
        case learning
        case unpracticed

        var label: String {
            switch self {
            case .stable: "已稳定"
            case .learning: "学习中"
            case .unpracticed: "未练习"
            }
        }
        var symbol: String {
            switch self {
            case .stable: "checkmark.circle"
            case .learning: "circle.lefthalf.filled"
            case .unpracticed: "circle.dotted"
            }
        }
    }

    public let occurrenceID: PracticeMeasureOccurrenceID
    public let state: State
    public let isResume: Bool
    public let isFocus: Bool

    public init(occurrenceID: PracticeMeasureOccurrenceID, state: State, isResume: Bool, isFocus: Bool) {
        self.occurrenceID = occurrenceID
        self.state = state
        self.isResume = isResume
        self.isFocus = isFocus
    }

    var label: String {
        "小节 \(occurrenceID.sourceMeasureID.sourceNumberToken ?? String(occurrenceID.sourceMeasureID.sourceMeasureIndex + 1))，\(state.label)\(isResume ? "，继续练习位置" : "")\(isFocus ? "，重点小节" : "")"
    }
}
