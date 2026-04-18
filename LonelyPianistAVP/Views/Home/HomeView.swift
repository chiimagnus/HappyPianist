import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @Bindable var viewModel: HomeViewModel
    @Bindable var arGuideViewModel: ARGuideViewModel

    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HomeHeaderView()
                HomeStatusSectionView(viewModel: viewModel)
                HomeScoreSectionView(viewModel: viewModel)
                Spacer(minLength: 0)
            }
            .padding(24)
        }
        .buttonBorderShape(.roundedRectangle)
        .fileImporter(
            isPresented: $viewModel.isImporterPresented,
            allowedContentTypes: [.xml, .musicXML],
            allowsMultipleSelection: false
        ) { result in
            viewModel.handleImportResult(result)
        }
        .sheet(isPresented: arGuideSheetIsPresented) {
            ARGuideSheetView(viewModel: arGuideViewModel)
        }
        .ornament(attachmentAnchor: .scene(.bottom), contentAlignment: .center) {
            HomeOrnamentBar(viewModel: viewModel)
        }
    }

    private var arGuideSheetIsPresented: Binding<Bool> {
        Binding(
            get: { viewModel.immersiveSpaceState != .closed },
            set: { isPresented in
                guard isPresented == false else { return }
                viewModel.stopARGuide(using: dismissImmersiveSpace)
            }
        )
    }
}

#Preview {
    let appModel = AppModel()
    HomeView(
        viewModel: HomeViewModel(appModel: appModel),
        arGuideViewModel: ARGuideViewModel(appModel: appModel)
    )
}
