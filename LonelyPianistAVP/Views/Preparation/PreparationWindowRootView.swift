import SwiftUI

struct PreparationWindowRootView: View {
    @Bindable var arGuideViewModel: ARGuideViewModel
    @Environment(WindowCoordinator.self) private var coordinator

    let services: AppServices
    let router: AppRouter

    init(
        services: AppServices,
        arGuideViewModel: ARGuideViewModel,
        router: AppRouter
    ) {
        _arGuideViewModel = Bindable(wrappedValue: arGuideViewModel)
        self.services = services
        self.router = router
    }

    var body: some View {
        Group {
            if let selectedMode = coordinator.pianoModeRegistry.mode(for: coordinator.flowState.selectedPianoModeID) {
                selectedMode.makePreparationView(arGuideViewModel: arGuideViewModel)
            } else {
                PianoTypePickerView()
            }
        }
        .environment(router)
    }
}
