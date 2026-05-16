import SwiftUI

struct PreparationWindowRootView: View {
    @Bindable var appState: AppState
    @Bindable var arGuideViewModel: ARGuideViewModel

    let services: AppServices
    let router: AppRouter

    init(
        appState: AppState,
        services: AppServices,
        arGuideViewModel: ARGuideViewModel,
        router: AppRouter
    ) {
        _appState = Bindable(wrappedValue: appState)
        _arGuideViewModel = Bindable(wrappedValue: arGuideViewModel)
        self.services = services
        self.router = router
    }

    var body: some View {
        AppRootView(
            appState: appState,
            services: services,
            arGuideViewModel: arGuideViewModel,
            router: router
        )
        .environment(router)
    }
}

