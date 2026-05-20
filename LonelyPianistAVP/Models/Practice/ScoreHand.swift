enum ScoreHand: String, CaseIterable {
    case right
    case left

    static func fromStaff(_ staff: Int?) -> ScoreHand {
        guard let staff else { return .right }
        if staff <= 1 { return .right }
        return .left
    }
}
