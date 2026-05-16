enum CalibrationCardStage: Hashable {
    case capturingA0
    case capturingC8
    case completed
    case error

    init(phase: ARGuideViewModel.CalibrationPhase) {
        switch phase {
            case .capturingA0, .transitionA0:
                self = .capturingA0
            case .capturingC8, .transitionC8:
                self = .capturingC8
            case .completed:
                self = .completed
            case .error:
                self = .error
        }
    }
}
