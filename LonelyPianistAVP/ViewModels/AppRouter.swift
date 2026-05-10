import Foundation

@MainActor
@Observable
final class AppRouter {
    enum Route: Hashable {
        case typePicker
        case realPreparation
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
        case .real:
            route = .realPreparation
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

    func exitToTypePicker(reason: String) {
        flowState.pianoKind = nil
        route = .typePicker
    }
}
