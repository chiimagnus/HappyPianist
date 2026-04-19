import SwiftUI

@main
struct LonelyPianistAVPApp: App {

    @State private var appModel: AppModel
    @State private var homeViewModel: HomeViewModel
    @State private var arGuideViewModel: ARGuideViewModel

    init() {
        let appModel = AppModel()
        appModel.loadStoredCalibrationIfPossible()
        _appModel = State(initialValue: appModel)
        _homeViewModel = State(initialValue: HomeViewModel(appModel: appModel))
        _arGuideViewModel = State(initialValue: ARGuideViewModel(appModel: appModel))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(homeViewModel: homeViewModel, arGuideViewModel: arGuideViewModel)
        }
        .windowStyle(.automatic)

        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            ImmersiveView(viewModel: arGuideViewModel)
                .onAppear {
                    appModel.immersiveSpaceState = .open
                }
                .onDisappear {
                    appModel.immersiveSpaceState = .closed
                }
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
