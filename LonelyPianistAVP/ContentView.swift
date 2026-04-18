import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var homeViewModel: HomeViewModel
    @Bindable var arGuideViewModel: ARGuideViewModel

    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HomeHeaderView()
                HomeStatusSectionView(viewModel: homeViewModel)
                HomeScoreSectionView(viewModel: homeViewModel)
                Spacer(minLength: 0)
            }
            .padding(24)
        }
        .buttonBorderShape(.roundedRectangle)
        .fileImporter(
            isPresented: $homeViewModel.isImporterPresented,
            allowedContentTypes: [.xml, .musicXML],
            allowsMultipleSelection: false
        ) { result in
            homeViewModel.handleImportResult(result)
        }
        .sheet(isPresented: arGuideSheetIsPresented) {
            ARGuideSheetView(viewModel: arGuideViewModel)
        }
        .ornament(attachmentAnchor: .scene(.bottom), contentAlignment: .center) {
            HomeOrnamentBar(viewModel: homeViewModel)
        }
    }

    private var arGuideSheetIsPresented: Binding<Bool> {
        Binding(
            get: { homeViewModel.immersiveSpaceState != .closed },
            set: { isPresented in
                guard isPresented == false else { return }
                homeViewModel.stopARGuide(using: dismissImmersiveSpace)
            }
        )
    }
}

#Preview {
    let appModel = AppModel()
    ContentView(
        homeViewModel: HomeViewModel(appModel: appModel),
        arGuideViewModel: ARGuideViewModel(appModel: appModel)
    )
}
