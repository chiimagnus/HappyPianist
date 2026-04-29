import SwiftUI

struct AppRootView: View {
    @Bindable var appState: AppState
    @Bindable var arGuideViewModel: ARGuideViewModel
    @State private var homeViewModel: HomeViewModel
    @State private var songLibraryViewModel: SongLibraryViewModel

    init(appState: AppState, services: AppServices, arGuideViewModel: ARGuideViewModel) {
        _appState = Bindable(wrappedValue: appState)
        _arGuideViewModel = Bindable(wrappedValue: arGuideViewModel)
        _homeViewModel = State(initialValue: HomeViewModel(appState: appState))
        _songLibraryViewModel = State(initialValue: SongLibraryViewModel(appState: appState))
    }

    var body: some View {
        ContentView(
            homeViewModel: homeViewModel,
            arGuideViewModel: arGuideViewModel,
            songLibraryViewModel: songLibraryViewModel
        )
    }
}
