import SwiftUI
import UniformTypeIdentifiers

struct LibraryWindowRootView: View {
  @Environment(WindowTransitionState.self) private var windowState
  @Environment(\.openWindow) private var openWindow
  @Environment(\.dismissWindow) private var dismissWindow
  @Environment(\.scenePhase) private var scenePhase

  @Bindable var appState: AppState
  @State private var songLibraryViewModel: SongLibraryViewModel
  @State private var diagnosticsViewModel: DiagnosticsViewModel

  init(
    appState: AppState,
    songLibraryViewModel: SongLibraryViewModel,
    diagnosticsViewModel: DiagnosticsViewModel
  ) {
    _appState = Bindable(wrappedValue: appState)
    _songLibraryViewModel = State(initialValue: songLibraryViewModel)
    _diagnosticsViewModel = State(initialValue: diagnosticsViewModel)
  }

  var body: some View {
    LibraryContentView(
      songLibraryViewModel: songLibraryViewModel,
      diagnosticsViewModel: diagnosticsViewModel,
      onBackToPreparation: {
        windowState.resetToPreparation(reason: "user tapped back from library window")
        windowState.beginTransition(from: .library, to: .preparation)
        openWindow(id: WindowID.preparation)
      },
      onStartPractice: {
        windowState.beginTransition(from: .library, to: .practice)
        openWindow(id: WindowID.practice)
      }
    )
    .onChange(of: scenePhase) {
      guard scenePhase == .active else { return }
      dismissPendingSourceIfNeeded()
    }
    .onAppear {
      dismissPendingSourceIfNeeded()
    }
  }

  private func dismissPendingSourceIfNeeded() {
    guard let transition = windowState.consumePendingTransition(to: .library) else { return }
    withTransaction(\.dismissBehavior, .destructive) {
      dismissWindow(id: transition.fromWindowID)
    }
  }
}

struct LibraryContentView: View {
  @Bindable var songLibraryViewModel: SongLibraryViewModel
  @Bindable var diagnosticsViewModel: DiagnosticsViewModel
  let onBackToPreparation: @MainActor () -> Void
  let onStartPractice: @MainActor () -> Void

  var body: some View {
    SongLibraryView(
      viewModel: songLibraryViewModel,
      diagnosticsViewModel: diagnosticsViewModel,
      onBackToPreparation: onBackToPreparation,
      onStartPractice: onStartPractice
    )
    .fileImporter(
      isPresented: $songLibraryViewModel.isMusicXMLImporterPresented,
      allowedContentTypes: [.xml, .musicXML, .compressedMusicXML],
      allowsMultipleSelection: true
    ) { result in
      do {
        songLibraryViewModel.importMusicXML(from: try result.get())
      } catch {
        songLibraryViewModel.errorMessage = "导入失败：\(error.localizedDescription)"
      }
    }
  }
}
