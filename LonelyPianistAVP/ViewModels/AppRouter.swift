import Observation
import os

@MainActor
@Observable
final class AppRouter {
    private static let logger = Logger(subsystem: "LonelyPianistAVP", category: "AppRouter")

    enum Route: Hashable {
        case typePicker
        case preparation
        case library
        case practice
    }

    let flowState: FlowState
    let pianoModeRegistry: PianoModeRegistryProtocol
    var route: Route = .typePicker

    init(flowState: FlowState, pianoModeRegistry: PianoModeRegistryProtocol) {
        self.flowState = flowState
        self.pianoModeRegistry = pianoModeRegistry
    }

    var pianoModes: [any PianoModeProtocol] {
        pianoModeRegistry.modes
    }

    var selectedPianoMode: (any PianoModeProtocol)? {
        pianoModeRegistry.mode(for: flowState.selectedPianoModeID)
    }

    func selectPianoMode(_ mode: any PianoModeProtocol) {
        flowState.selectedPianoModeID = mode.id
        route = .preparation
    }

    func goToLibrary() {
        route = .library
    }

    func goToPractice() {
        route = .practice
    }

    var canProceedToLibrary: Bool {
        selectedPianoMode?.canProceedToLibrary(flowState: flowState) ?? false
    }

    func exitToTypePicker(reason: String) {
        Self.logger.info("exitToTypePicker: \(reason)")
        flowState.clearSongAndSteps()
        flowState.isCalibrationCompleted = false
        flowState.isVirtualPianoPlaced = false
        flowState.bluetoothMIDISourceCount = 0
        flowState.selectedPianoModeID = nil
        route = .typePicker
    }
}
