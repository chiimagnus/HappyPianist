import SwiftUI

struct ContentView: View {
    @Bindable var homeViewModel: HomeViewModel
    @Bindable var arGuideViewModel: ARGuideViewModel

    var body: some View {
        HomeView(viewModel: homeViewModel, arGuideViewModel: arGuideViewModel)
    }
}

#Preview {
    let appModel = AppModel()
    ContentView(
        homeViewModel: HomeViewModel(appModel: appModel),
        arGuideViewModel: ARGuideViewModel(appModel: appModel)
    )
}
