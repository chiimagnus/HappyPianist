import Observation
import SwiftUI

struct MainWindowView: View {
    @Bindable var viewModel: LonelyPianistViewModel

    var body: some View {
        NavigationSplitView {
            List(selection: sidebarSelection) {
                ForEach(LonelyPianistViewModel.MainWindowSection.allCases) { section in
                    NavigationLink(value: section) {
                        Label(section.rawValue, systemImage: section.systemImage)
                    }
                }
            }
            .listStyle(.sidebar)
        } detail: {
            switch viewModel.selectedMainWindowSection {
            case .runtime:
                RuntimePanelView(viewModel: viewModel)
                    .navigationTitle("Runtime")

            case .mappings:
                MappingsPanelView(viewModel: viewModel)
                    .navigationTitle("Mappings")

            case .recorder:
                RecorderPanelView(viewModel: viewModel)
                    .navigationTitle("Recorder")

            case .dialogue:
                DialogueControlView(viewModel: viewModel)
                    .navigationTitle("Dialogue")
            }
        }
    }

    private var sidebarSelection: Binding<LonelyPianistViewModel.MainWindowSection?> {
        Binding(
            get: { Optional(viewModel.selectedMainWindowSection) },
            set: { newValue in
                guard let newValue else { return }
                viewModel.selectedMainWindowSection = newValue
            }
        )
    }
}
