import SwiftUI

struct PreparationWindowRootView: View {
    @Bindable var arGuideViewModel: ARGuideViewModel
    @Environment(WindowCoordinator.self) private var coordinator

    init(
        arGuideViewModel: ARGuideViewModel
    ) {
        _arGuideViewModel = Bindable(wrappedValue: arGuideViewModel)
    }

    var body: some View {
        Group {
            if let selectedMode = coordinator.pianoModeRegistry.mode(for: coordinator.flowState.selectedPianoModeID) {
                selectedMode.makePreparationView(arGuideViewModel: arGuideViewModel)
            } else {
                PianoTypePickerView()
            }
        }
        .frame(minWidth: 860, idealWidth: 900, minHeight: 520, idealHeight: 650)
    }
}
