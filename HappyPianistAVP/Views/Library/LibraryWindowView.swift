import Diagnostics
import Library
import MusicXML
import SwiftUI
import UniformTypeIdentifiers

struct LibraryWindowRootView: View {
    @Environment(PianoSetupCoordinator.self) private var pianoSetupCoordinator
    @Environment(\.pushWindow) private var pushWindow
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.scenePhase) private var scenePhase

    @Bindable var appState: AppState
    @Bindable var arGuideViewModel: ARGuideViewModel
    @State private var spatialOpenError: String?
    @State private var isOpeningSpatialLibrary = false
    @State private var songLibraryViewModel: SongLibraryViewModel
    @State private var practiceLaunchViewModel: PracticeLaunchViewModel
    @State private var diagnosticsViewModel: DiagnosticsViewModel

    init(
        appState: AppState,
        arGuideViewModel: ARGuideViewModel,
        songLibraryViewModel: SongLibraryViewModel,
        practiceLaunchViewModel: PracticeLaunchViewModel,
        diagnosticsViewModel: DiagnosticsViewModel
    ) {
        _appState = Bindable(wrappedValue: appState)
        _arGuideViewModel = Bindable(wrappedValue: arGuideViewModel)
        _songLibraryViewModel = State(initialValue: songLibraryViewModel)
        _practiceLaunchViewModel = State(initialValue: practiceLaunchViewModel)
        _diagnosticsViewModel = State(initialValue: diagnosticsViewModel)
    }

    var body: some View {
        LibraryContentView(
            songLibraryViewModel: songLibraryViewModel,
            diagnosticsViewModel: diagnosticsViewModel,
            isPracticeSetupReady: pianoSetupCoordinator.isSetupReady && !practiceLaunchViewModel.ownsPracticeLifecycle,
            onChoosePiano: {
                guard !practiceLaunchViewModel.ownsPracticeLifecycle else {
                    openWindow(id: WindowID.practice)
                    return
                }
                pianoSetupCoordinator.reset()
                pushWindow(id: WindowID.preparation)
            },
            onStartPractice: { songID in
                guard pianoSetupCoordinator.isSetupReady, !practiceLaunchViewModel.ownsPracticeLifecycle else { return }
                practiceLaunchViewModel.request(songID: songID)
                pushWindow(id: WindowID.practice)
            }
        )
        .safeAreaInset(edge: .top) {
            if spatialLaunchRoute != .unavailable {
                VStack(spacing: 8) {
                    Button(spatialEntryTitle, systemImage: "books.vertical", action: enterSpatialLibrary)
                        .buttonStyle(.borderedProminent)
                        .disabled(isOpeningSpatialLibrary || songLibraryViewModel.importState.isActive)
                    if let spatialOpenError {
                        Text(spatialOpenError).font(.callout)
                    }
                    if spatialLaunchRoute == .alreadyOpen {
                        switch arGuideViewModel.spatialLibraryViewModel.state {
                        case .awaitingDevicePose:
                            ProgressView("正在定位空间曲库")
                        case .placementFailed:
                            Text("暂时无法定位曲库，请面向前方重试。")
                            Button("重新定位", systemImage: "arrow.clockwise") {
                                arGuideViewModel.startTrackingIfNeeded()
                                arGuideViewModel.spatialLibraryViewModel.retryPlacement()
                            }
                        case .inactive, .placed:
                            EmptyView()
                        }
                    }
                }
                .padding()
            }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                songLibraryViewModel.refreshSelectedPracticeSnapshot()
            } else if appState.immersiveSpaceState == .closed {
                songLibraryViewModel.scorePreview.close()
            }
        }
        .onAppear {
            songLibraryViewModel.refreshSelectedPracticeSnapshot()
        }
        .onChange(of: shouldYieldToSpatialLibrary, initial: true) {
            if shouldYieldToSpatialLibrary {
                dismissWindow(id: WindowID.library)
            }
        }
    }

    private var shouldYieldToSpatialLibrary: Bool {
        appState.immersiveSpaceState == .open
            && appState.immersiveMode == .library
            && arGuideViewModel.spatialLibraryViewModel.validPlacement != nil
    }

    private var spatialLaunchRoute: SpatialLibraryLaunchRoute {
        .resolve(
            hasEntries: !songLibraryViewModel.entries.isEmpty,
            practiceOwnsLifecycle: practiceLaunchViewModel.ownsPracticeLifecycle,
            immersiveSpaceState: appState.immersiveSpaceState,
            immersiveMode: appState.immersiveMode
        )
    }

    private var spatialEntryTitle: String {
        switch spatialLaunchRoute {
        case .unavailable, .enterSpatialLibrary:
            spatialOpenError == nil ? "进入空间曲库" : "重试空间曲库"
        case .alreadyOpen:
            "关闭空间曲库"
        case .returnToPractice:
            "返回练习（结束后进入曲库）"
        case .returnToPreparation:
            "返回钢琴设置"
        }
    }

    private func enterSpatialLibrary() {
        guard !isOpeningSpatialLibrary else { return }
        switch spatialLaunchRoute {
        case .unavailable:
            return
        case .returnToPractice:
            openWindow(id: WindowID.practice)
        case .returnToPreparation:
            openWindow(id: WindowID.preparation)
        case .alreadyOpen, .enterSpatialLibrary:
            isOpeningSpatialLibrary = true
            Task { @MainActor in
                defer { isOpeningSpatialLibrary = false }
                if spatialLaunchRoute == .alreadyOpen {
                    await arGuideViewModel.closeImmersive(using: makeImmersiveSpaceDismissHandler(dismissImmersiveSpace))
                } else if spatialLaunchRoute == .enterSpatialLibrary {
                    spatialOpenError = await arGuideViewModel.openImmersive(mode: .library, using: makeImmersiveSpaceOpenHandler(openImmersiveSpace))
                }
            }
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
        arGuideViewModel: graph.arGuideViewModel,
        songLibraryViewModel: graph.songLibraryViewModel,
        practiceLaunchViewModel: graph.practiceLaunchViewModel,
        diagnosticsViewModel: graph.diagnosticsViewModel
    )
    .environment(graph.pianoSetupCoordinator)
}
