import Foundation
import SwiftUI

#if DEBUG
    enum AppUICaptureRoute: Equatable {
        case library
        case spatialLibrary
        case spatialSpread
        case practice(songID: UUID)

        init?(arguments: [String]) {
            guard let destination = Self.value(after: "--ui-capture", in: arguments) else {
                return nil
            }
            switch destination {
            case "library":
                self = .library
            case "spatial-library":
                self = .spatialLibrary
            case "spatial-spread":
                self = .spatialSpread
            case "practice":
                guard let rawSongID = Self.value(after: "--song-id", in: arguments),
                      let songID = UUID(uuidString: rawSongID)
                else { return nil }
                self = .practice(songID: songID)
            default:
                return nil
            }
        }

        private static func value(after flag: String, in arguments: [String]) -> String? {
            guard let index = arguments.firstIndex(of: flag),
                  arguments.indices.contains(index + 1)
            else { return nil }
            return arguments[index + 1]
        }
    }
#endif

@main
struct HappyPianistAVPApp: App {
    @State private var appState: AppState
    private let graph: LiveAppGraph
    #if DEBUG
        private let uiCaptureRoute: AppUICaptureRoute?
        @State private var didPerformSpatialUICapture = false
    #endif

    init() {
        let graph = LiveAppGraph.make()
        self.graph = graph
        _appState = State(initialValue: graph.appState)
        #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            let uiCaptureRoute = AppUICaptureRoute(arguments: arguments)
            precondition(
                arguments.contains("--ui-capture") == false || uiCaptureRoute != nil,
                "Invalid --ui-capture arguments"
            )
            self.uiCaptureRoute = uiCaptureRoute
            if case let .practice(songID)? = uiCaptureRoute {
                graph.practiceLaunchViewModel.request(songID: songID)
            }
        #endif
    }

    var body: some Scene {
        Window("Library", id: WindowID.library) {
            mainWindowRoot
                .environment(graph.pianoSetupCoordinator)
        }
        .windowResizability(.contentSize)

        Window("Preparation", id: WindowID.preparation) {
            PreparationWindowRootView(arGuideViewModel: graph.arGuideViewModel)
                .environment(graph.pianoSetupCoordinator)
        }
        .windowResizability(.contentSize)

        Window("Practice", id: WindowID.practice) {
            PracticeWindowRootView(
                arGuideViewModel: graph.arGuideViewModel,
                launchViewModel: graph.practiceLaunchViewModel
            )
        }
        .windowResizability(.contentSize)

        ImmersiveSpace(id: appState.immersiveSpaceID) {
            ImmersiveView(
                viewModel: graph.arGuideViewModel,
                songLibraryViewModel: graph.songLibraryViewModel,
                spatialLibraryViewModel: graph.spatialLibraryViewModel
            )
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }

    @ViewBuilder
    private var mainWindowRoot: some View {
        #if DEBUG
            if let uiCaptureRoute {
                uiCaptureRoot(for: uiCaptureRoute)
            } else {
                libraryWindowRoot
            }
        #else
            libraryWindowRoot
        #endif
    }

    private var libraryWindowRoot: some View {
        LibraryWindowRootView(
            appState: appState,
            arGuideViewModel: graph.arGuideViewModel,
            songLibraryViewModel: graph.songLibraryViewModel,
            practiceLaunchViewModel: graph.practiceLaunchViewModel,
            diagnosticsViewModel: graph.diagnosticsViewModel
        )
    }

    #if DEBUG
        @ViewBuilder
        private func uiCaptureRoot(for route: AppUICaptureRoute) -> some View {
            switch route {
            case .library, .spatialLibrary, .spatialSpread:
                LibraryWindowRootView(
                    appState: appState,
                    arGuideViewModel: graph.arGuideViewModel,
                    songLibraryViewModel: graph.songLibraryViewModel,
                    practiceLaunchViewModel: graph.practiceLaunchViewModel,
                    diagnosticsViewModel: graph.diagnosticsViewModel
                )
                .modifier(SpatialLibraryCaptureModifier(graph: graph, route: route, didPerformCapture: $didPerformSpatialUICapture))
            case .practice:
                PracticeWindowRootView(
                    arGuideViewModel: graph.arGuideViewModel,
                    launchViewModel: graph.practiceLaunchViewModel
                )
            }
        }
    #endif
}

#if DEBUG
    private struct SpatialLibraryCaptureModifier: ViewModifier {
        let graph: LiveAppGraph
        let route: AppUICaptureRoute
        @Binding var didPerformCapture: Bool
        @Environment(\.openImmersiveSpace) private var openImmersiveSpace

        func body(content: Content) -> some View {
            content.task {
                guard route == .spatialLibrary || route == .spatialSpread else { return }
                guard !didPerformCapture else { return }
                didPerformCapture = true
                await graph.songLibraryViewModel.loadLibrary()
                guard !graph.songLibraryViewModel.entries.isEmpty else { return }
                let failure = await graph.arGuideViewModel.openImmersive(mode: .library, using: makeImmersiveSpaceOpenHandler(openImmersiveSpace))
                if failure == nil, route == .spatialSpread {
                    graph.songLibraryViewModel.openSelectedScore()
                }
            }
        }
    }
#endif
