import SwiftUI

struct AppRootView: View {
    @Bindable var appState: AppState
    @Bindable var arGuideViewModel: ARGuideViewModel
    @State private var songLibraryViewModel: SongLibraryViewModel
    let router: AppRouter

    init(appState: AppState, services: AppServices, arGuideViewModel: ARGuideViewModel, router: AppRouter) {
        _appState = Bindable(wrappedValue: appState)
        _arGuideViewModel = Bindable(wrappedValue: arGuideViewModel)
        _songLibraryViewModel = State(initialValue: SongLibraryViewModel(
            appState: appState,
            flowState: router.flowState,
            practicePreparationService: services.practicePreparationService
        ))
        self.router = router
    }

    var body: some View {
        @Bindable var router = router

        switch router.route {
        case .typePicker:
            PianoTypePickerView()
        case .realPreparation:
            RealPianoPreparationView(viewModel: arGuideViewModel)
        case .bluetoothMIDIPreparation:
            Text("Bluetooth MIDI 准备中…")
        case .virtualPreparation:
            VirtualPianoPreparationView(viewModel: arGuideViewModel)
        case .library:
            LibraryFlowView(songLibraryViewModel: songLibraryViewModel)
        case .practice:
            PracticeFlowView(viewModel: arGuideViewModel)
        }
    }
}
