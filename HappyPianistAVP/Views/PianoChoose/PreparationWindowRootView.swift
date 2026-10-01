import SwiftUI

struct PreparationWindowRootView: View {
    @Bindable var arGuideViewModel: ARGuideViewModel
    @Environment(PianoSetupCoordinator.self) private var pianoSetupCoordinator
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @State private var isFinishingSetup = false

    init(
        arGuideViewModel: ARGuideViewModel
    ) {
        _arGuideViewModel = Bindable(wrappedValue: arGuideViewModel)
    }

    var body: some View {
        let actions = PreparationNavigationActions(
            backToTypePicker: {
                pianoSetupCoordinator.reset()
            },
            finishSetup: finishSetup
        )

        Group {
            if let selectedMode = pianoSetupCoordinator.selectedMode {
                PianoModePreparationRouterView(
                    route: selectedMode.preparationRoute,
                    arGuideViewModel: arGuideViewModel
                )
            } else {
                PianoTypePickerView()
            }
        }
        .environment(\.preparationNavigationActions, actions)
        .disabled(isFinishingSetup)
    }

    private func finishSetup() {
        guard isFinishingSetup == false else { return }
        isFinishingSetup = true

        Task { @MainActor in
            let dismissHandler = makeImmersiveSpaceDismissHandler(dismissImmersiveSpace)
            await arGuideViewModel.closeImmersive(using: dismissHandler)
            dismissWindow(id: WindowID.preparation)
        }
    }
}

struct PianoModePreparationRouterView: View {
    let route: PianoModePreparationRoute
    @Bindable var arGuideViewModel: ARGuideViewModel

    init(route: PianoModePreparationRoute, arGuideViewModel: ARGuideViewModel) {
        self.route = route
        _arGuideViewModel = Bindable(wrappedValue: arGuideViewModel)
    }

    var body: some View {
        switch route {
        case .realPiano:
            RealPianoPreparationView(viewModel: arGuideViewModel)
        case .bluetoothMIDI:
            BluetoothMIDIPreparationView(viewModel: arGuideViewModel)
        case .virtualPiano:
            VirtualPianoPreparationView(viewModel: arGuideViewModel)
        }
    }
}

struct PreparationNavigationActions {
    var backToTypePicker: @MainActor () -> Void
    var finishSetup: @MainActor () -> Void

    static let noop = PreparationNavigationActions(
        backToTypePicker: {},
        finishSetup: {}
    )
}

extension EnvironmentValues {
    @Entry var preparationNavigationActions: PreparationNavigationActions = .noop
}
