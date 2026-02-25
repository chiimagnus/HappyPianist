import AppKit
import MenuBarDockKit
import Observation
import SwiftUI

struct MainWindowView: View {
    @Bindable var viewModel: PianoKeyViewModel
    @State private var mainWindow: NSWindow?
    @State private var mainWindowDockVisibilityController = MainWindowDockVisibilityController()

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

            case .settings:
                SettingsView()
                    .navigationTitle("Settings")
            }
        }
        .background(
            WindowReader(window: $mainWindow) { newWindow in
                mainWindowDockVisibilityController.attachWindow(newWindow)
            }
        )
        .onDisappear {
            mainWindowDockVisibilityController.reset()
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
