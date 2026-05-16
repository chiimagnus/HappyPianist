import Observation
import SwiftUI
import os

@MainActor
@Observable
final class WindowCoordinator {
    private static let logger = Logger(subsystem: "LonelyPianistAVP", category: "WindowCoordinator")

    enum Window: String, Hashable {
        case preparation
        case library
        case practice

        var id: String { rawValue }
    }

    let flowState: FlowState
    let pianoModeRegistry: PianoModeRegistryProtocol

    init(flowState: FlowState, pianoModeRegistry: PianoModeRegistryProtocol) {
        self.flowState = flowState
        self.pianoModeRegistry = pianoModeRegistry
    }

    func transition(
        from currentWindow: Window?,
        to targetWindow: Window,
        openWindow: OpenWindowAction,
        dismissWindow: DismissWindowAction
    ) {
        guard currentWindow != targetWindow else { return }

        Self.logger.info("transition: \(String(describing: currentWindow?.id)) -> \(targetWindow.id)")
        openWindow(id: targetWindow.id)

        if let currentWindow {
            dismissWindow(id: currentWindow.id)
        } else {
            dismissWindow()
        }
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
