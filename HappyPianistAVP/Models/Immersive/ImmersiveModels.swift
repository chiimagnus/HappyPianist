struct ARTrackingRequirements: OptionSet {
    let rawValue: UInt8

    static let hand = Self(rawValue: 1 << 0)
    static let world = Self(rawValue: 1 << 1)
    static let horizontalPlanes = Self(rawValue: 1 << 2)

    static let calibration: Self = [.hand, .world]

    static func practice(
        base: Self,
        requiresHorizontalPlanePlacement: Bool
    ) -> Self {
        var requirements = base
        if requiresHorizontalPlanePlacement {
            requirements.insert(.horizontalPlanes)
        } else {
            requirements.remove(.horizontalPlanes)
        }
        return requirements
    }
}

enum ARTrackingProviderState: Equatable {
    case idle
    case running
    case unsupported
    case unauthorized
    case disabled
    case stopped
    case failed(reason: String)

    var description: String {
        switch self {
        case .idle:
            "idle"
        case .running:
            "running"
        case .unsupported:
            "unsupported"
        case .unauthorized:
            "unauthorized"
        case .disabled:
            "disabled"
        case .stopped:
            "stopped"
        case let .failed(reason):
            "failed(\(reason))"
        }
    }
}
