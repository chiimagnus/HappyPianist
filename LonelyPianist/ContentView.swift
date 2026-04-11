import Observation
import SwiftUI

struct MainWindowView: View {
    @Bindable var viewModel: LonelyPianistViewModel
    @State private var isMappingsInspectorPresented = false

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
                PianoMappingsEditorView(viewModel: viewModel, isInspectorPresented: $isMappingsInspectorPresented)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .navigationTitle("Mappings")
                    .toolbar {
                        ToolbarItemGroup(placement: .automatic) {
                            Spacer()
                            Button {
                                isMappingsInspectorPresented.toggle()
                            } label: {
                                Label(
                                    isMappingsInspectorPresented ? "Hide Inspector" : "Show Inspector",
                                    systemImage: "sidebar.right"
                                )
                            }
                        }
                    }

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
