import SwiftUI

struct PreparationWindowRootView: View {
    @Bindable var arGuideViewModel: ARGuideViewModel
    @Environment(WindowCoordinator.self) private var coordinator
    @Environment(\.pushWindow) private var pushWindow
    @Environment(\.scenePhase) private var scenePhase

    init(
        arGuideViewModel: ARGuideViewModel
    ) {
        _arGuideViewModel = Bindable(wrappedValue: arGuideViewModel)
    }

    var body: some View {
        let actions = PreparationNavigationActions(
            backToTypePicker: {
                coordinator.resetToPreparation(reason: "user tapped back from preparation")
            },
            nextToLibrary: {
                pushWindow(id: WindowIDs.library)
            }
            ,
            pushPractice: {
                pushWindow(id: WindowIDs.practice)
            }
        )

        Group {
            if let selectedMode = coordinator.pianoModeRegistry.mode(for: coordinator.flowState.selectedPianoModeID) {
                selectedMode.makePreparationView(arGuideViewModel: arGuideViewModel)
            } else {
                PianoTypePickerView()
            }
        }
        .environment(\.preparationNavigationActions, actions)
        .frame(minWidth: 860, idealWidth: 900, minHeight: 520, idealHeight: 650)
        .onChange(of: scenePhase) {
            guard scenePhase == .active else { return }
            guard let target = coordinator.consumePendingPushTarget() else { return }
            pushWindow(id: target.id)
        }
        .onAppear {
            guard let target = coordinator.consumePendingPushTarget() else { return }
            pushWindow(id: target.id)
        }
    }
}
