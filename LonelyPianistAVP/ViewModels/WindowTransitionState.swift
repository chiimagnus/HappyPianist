import Observation
import os

@MainActor
@Observable
final class WindowTransitionState {
    private static let logger = Logger(subsystem: "LonelyPianistAVP", category: "WindowTransitionState")

    enum Window: Hashable {
        case preparation
        case library
        case practice

        var id: String {
            switch self {
                case .preparation:
                    WindowID.preparation
                case .library:
                    WindowID.library
                case .practice:
                    WindowID.practice
            }
        }
    }

    let practiceSetupState: PracticeSetupState
    let pianoModeRegistry: PianoModeRegistryProtocol
    struct PendingTransition: Equatable {
        var fromWindowID: String
        var toWindowID: String
    }

    var pendingTransition: PendingTransition?

    init(practiceSetupState: PracticeSetupState, pianoModeRegistry: PianoModeRegistryProtocol) {
        self.practiceSetupState = practiceSetupState
        self.pianoModeRegistry = pianoModeRegistry
    }

    func beginTransition(from fromWindow: Window, to toWindow: Window) {
        Self.logger.info("beginTransition: \(fromWindow.id) -> \(toWindow.id)")
        pendingTransition = PendingTransition(fromWindowID: fromWindow.id, toWindowID: toWindow.id)
    }

    func consumePendingTransition(to toWindow: Window) -> PendingTransition? {
        guard let pendingTransition else { return nil }
        guard pendingTransition.toWindowID == toWindow.id else { return nil }
        self.pendingTransition = nil
        return pendingTransition
    }

    func resetToPreparation(reason: String) {
        Self.logger.info("resetToPreparation: \(reason)")
        practiceSetupState.clearSongAndSteps()
        practiceSetupState.isCalibrationCompleted = false
        practiceSetupState.isVirtualPianoPlaced = false
        practiceSetupState.bluetoothMIDISourceCount = 0
        practiceSetupState.selectedPianoModeID = nil
    }
}
