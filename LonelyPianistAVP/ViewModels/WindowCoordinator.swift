import Observation
import os

@MainActor
@Observable
final class WindowCoordinator {
    private static let logger = Logger(subsystem: "LonelyPianistAVP", category: "WindowCoordinator")

    enum Window: Hashable {
        case preparation
        case library
        case practice

        var id: String {
            switch self {
            case .preparation:
                WindowIDs.preparation
            case .library:
                WindowIDs.library
            case .practice:
                WindowIDs.practice
            }
        }
    }

    let flowState: FlowState
    let pianoModeRegistry: PianoModeRegistryProtocol
    struct PendingTransition: Equatable {
        var fromWindowID: String
        var toWindowID: String
    }

    var pendingTransition: PendingTransition?

    init(flowState: FlowState, pianoModeRegistry: PianoModeRegistryProtocol) {
        self.flowState = flowState
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
        flowState.clearSongAndSteps()
        flowState.isCalibrationCompleted = false
        flowState.isVirtualPianoPlaced = false
        flowState.bluetoothMIDISourceCount = 0
        flowState.selectedPianoModeID = nil
    }
}
