import Observation
import os

@MainActor
@Observable
final class AppRouter {
    private static let logger = Logger(subsystem: "LonelyPianistAVP", category: "AppRouter")

    enum Route: Hashable {
        case typePicker
        case realPreparation
        case bluetoothMIDIPreparation
        case virtualPreparation
        case library
        case practice
    }

    let flowState: FlowState
    var route: Route = .typePicker

    init(flowState: FlowState) {
        self.flowState = flowState
    }

    func selectPianoKind(_ kind: PianoKind) {
        flowState.pianoKind = kind
        switch kind {
        case .realAudio:
            route = .realPreparation
        case .realBluetoothMIDI:
            route = .bluetoothMIDIPreparation
        case .virtual:
            route = .virtualPreparation
        }
    }

    func goToLibrary() {
        route = .library
    }

    func goToPractice() {
        route = .practice
    }

    var canProceedToLibrary: Bool {
        switch flowState.pianoKind {
        case .realAudio:
            return flowState.isCalibrationCompleted
        case .realBluetoothMIDI:
            return flowState.isCalibrationCompleted && flowState.bluetoothMIDISourceCount > 0
        case .virtual:
            return flowState.isVirtualPianoPlaced
        case .none:
            return false
        }
    }

    func exitToTypePicker(reason: String) {
        Self.logger.info("exitToTypePicker: \(reason)")
        flowState.clearSongAndSteps()
        flowState.isCalibrationCompleted = false
        flowState.isVirtualPianoPlaced = false
        flowState.bluetoothMIDISourceCount = 0
        flowState.pianoKind = nil
        route = .typePicker
    }
}
