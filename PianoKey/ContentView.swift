import Observation
import SwiftUI

struct MainWindowView: View {
    @Bindable var viewModel: PianoKeyViewModel

    var body: some View {
        NavigationSplitView {
            List(selection: sidebarSelection) {
                ForEach(PianoKeyViewModel.MainWindowSection.allCases) { section in
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
            }
        }
    }

    private var sidebarSelection: Binding<PianoKeyViewModel.MainWindowSection?> {
        Binding(
            get: { Optional(viewModel.selectedMainWindowSection) },
            set: { newValue in
                guard let newValue else { return }
                viewModel.selectedMainWindowSection = newValue
            }
        )
    }
}

