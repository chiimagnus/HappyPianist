import SwiftUI
import UniformTypeIdentifiers
import MusicXML

struct LibraryWindowRootView: View {
    @Environment(PianoSetupCoordinator.self) private var pianoSetupCoordinator
    @Environment(\.pushWindow) private var pushWindow
    @Environment(\.scenePhase) private var scenePhase

    @Bindable var appState: AppState
    @State private var songLibraryViewModel: SongLibraryViewModel
    @State private var practiceLaunchViewModel: PracticeLaunchViewModel
    @State private var diagnosticsViewModel: DiagnosticsViewModel

    init(
        appState: AppState,
        songLibraryViewModel: SongLibraryViewModel,
        practiceLaunchViewModel: PracticeLaunchViewModel,
        diagnosticsViewModel: DiagnosticsViewModel
    ) {
        _appState = Bindable(wrappedValue: appState)
        _songLibraryViewModel = State(initialValue: songLibraryViewModel)
        _practiceLaunchViewModel = State(initialValue: practiceLaunchViewModel)
        _diagnosticsViewModel = State(initialValue: diagnosticsViewModel)
    }

    var body: some View {
        LibraryContentView(
            songLibraryViewModel: songLibraryViewModel,
            diagnosticsViewModel: diagnosticsViewModel,
            isPracticeSetupReady: pianoSetupCoordinator.isSetupReady,
            onChoosePiano: {
                pianoSetupCoordinator.reset()
                pushWindow(id: WindowID.preparation)
            },
            onStartPractice: { songID in
                guard pianoSetupCoordinator.isSetupReady else { return }
                practiceLaunchViewModel.request(songID: songID)
                pushWindow(id: WindowID.practice)
            }
        )
        .onChange(of: scenePhase) {
            guard scenePhase == .active else { return }
            songLibraryViewModel.refreshSelectedPracticeSnapshot()
        }
        .onAppear {
            songLibraryViewModel.refreshSelectedPracticeSnapshot()
        }
    }
}

struct LibraryContentView: View {
    @Bindable var songLibraryViewModel: SongLibraryViewModel
    @Bindable var diagnosticsViewModel: DiagnosticsViewModel
    let isPracticeSetupReady: Bool
    let onChoosePiano: @MainActor () -> Void
    let onStartPractice: @MainActor (UUID) -> Void

    var body: some View {
        SongLibraryView(
            viewModel: songLibraryViewModel,
            diagnosticsViewModel: diagnosticsViewModel,
            isPracticeSetupReady: isPracticeSetupReady,
            onChoosePiano: onChoosePiano,
            onStartPractice: onStartPractice
        )
        .fileImporter(
            isPresented: $songLibraryViewModel.isMusicXMLImporterPresented,
            allowedContentTypes: [.xml, .musicXML, .compressedMusicXML],
            allowsMultipleSelection: true
        ) { result in
            do {
                let selectedURLs = try result.get()
                Task { @MainActor in
                    await songLibraryViewModel.importMusicXML(from: selectedURLs)
                }
            } catch {
                songLibraryViewModel.errorMessage = "导入失败：\(error.localizedDescription)"
            }
        }
    }
}

#Preview("曲库窗口") {
    let graph = LiveAppGraph.make()

    LibraryWindowRootView(
        appState: graph.appState,
        songLibraryViewModel: graph.songLibraryViewModel,
        practiceLaunchViewModel: graph.practiceLaunchViewModel,
        diagnosticsViewModel: graph.diagnosticsViewModel
    )
    .environment(graph.pianoSetupCoordinator)
}
