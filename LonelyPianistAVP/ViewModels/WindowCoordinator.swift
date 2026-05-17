import Observation
import SwiftUI
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
        transition(from: currentWindow, to: targetWindow) { id in
            openWindow(id: id)
        } dismiss: { shouldDismissCurrent in
            guard shouldDismissCurrent else { return }
            dismissWindow()
        }
    }

    func transition(
        from currentWindow: Window?,
        to targetWindow: Window,
        open: (String) -> Void,
        dismiss: (Bool) -> Void
    ) {
        guard currentWindow != targetWindow else { return }

        Self.logger.info("transition: \(String(describing: currentWindow?.id)) -> \(targetWindow.id)")
        open(targetWindow.id)
        dismiss(currentWindow != nil)
    }

    func resetToPreparation(reason: String) {
        Self.logger.info("resetToPreparation: \(reason)")
        flowState.clearSongAndSteps()
        flowState.isCalibrationCompleted = false
        flowState.isVirtualPianoPlaced = false
        flowState.bluetoothMIDISourceCount = 0
        flowState.selectedPianoModeID = nil
    }

    func openLibrary(dismissCurrent: Window?, openWindow: OpenWindowAction, dismissWindow: DismissWindowAction) {
        transition(from: dismissCurrent, to: .library, openWindow: openWindow, dismissWindow: dismissWindow)
    }

    func openPractice(dismissCurrent: Window?, openWindow: OpenWindowAction, dismissWindow: DismissWindowAction) {
        transition(from: dismissCurrent, to: .practice, openWindow: openWindow, dismissWindow: dismissWindow)
    }

    func openPreparation(dismissCurrent: Window?, openWindow: OpenWindowAction, dismissWindow: DismissWindowAction) {
        transition(from: dismissCurrent, to: .preparation, openWindow: openWindow, dismissWindow: dismissWindow)
    }
}
