import Diagnostics
import Library
import LibraryPresentation
import MusicXML
import Observation
import SwiftUI
import UniformTypeIdentifiers

private enum MacLibraryRoute: Hashable {
    case diagnostics
    case midiSettings
    case practice(UUID)
}

struct MacLibraryRootView: View {
    @Bindable var viewModel: MacLibraryViewModel
    @Bindable var midiSettingsViewModel: MIDISettingsViewModel
    @Bindable var diagnosticsViewModel: DiagnosticsViewModel
    @Bindable var practiceViewModel: MacPracticeViewModel
    @State private var path: [MacLibraryRoute] = []
    @State private var isFinishingPracticeNavigation = false

    private var audioImporterTypes: [UTType] {
        let types = AudioImportService.supportedFileExtensions.compactMap {
            UTType(filenameExtension: $0)
        }
        return types.isEmpty ? [.audio] : types
    }

    var body: some View {
        NavigationStack(path: navigationPath) {
            Group {
                switch viewModel.loadState {
                case .idle, .loading:
                    ProgressView("正在恢复曲库")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .ready:
                    MacLibraryView(viewModel: viewModel)
                case let .recoveryBlocked(message):
                    MacLibraryUnavailableView(
                        title: "曲库恢复需要处理",
                        message: message,
                        retry: { await viewModel.loadLibrary() }
                    )
                case .unavailable:
                    MacLibraryUnavailableView(
                        title: "暂时无法读取曲库",
                        message: "请检查存储后重试。",
                        retry: { await viewModel.loadLibrary() }
                    )
                }
            }
            .navigationDestination(for: MacLibraryRoute.self) { route in
                switch route {
                case .diagnostics:
                    MacDiagnosticsView(viewModel: diagnosticsViewModel)
                case .midiSettings:
                    MIDISettingsView(viewModel: midiSettingsViewModel)
                case let .practice(songID):
                    MacPracticeView(
                        songID: songID,
                        viewModel: practiceViewModel,
                        onExit: leavePractice
                    )
                }
            }
            .toolbar {
                NavigationLink(value: MacLibraryRoute.diagnostics) {
                    Label("诊断", systemImage: "stethoscope")
                }
                NavigationLink(value: MacLibraryRoute.midiSettings) {
                    Label("MIDI 设备", systemImage: "pianokeys")
                }
            }
            .task {
                await viewModel.loadLibrary()
            }
            .fileImporter(
                isPresented: $viewModel.isMusicXMLImporterPresented,
                allowedContentTypes: [.xml, .musicXML, .compressedMusicXML],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case let .success(urls):
                    Task {
                        await viewModel.importMusicXML(from: urls)
                    }
                case .failure:
                    viewModel.receiveImporterFailure()
                }
            }
            .fileImporter(
                isPresented: $viewModel.isAudioImporterPresented,
                allowedContentTypes: audioImporterTypes,
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case let .success(urls):
                    Task {
                        await viewModel.importAudio(from: urls)
                    }
                case .failure:
                    viewModel.receiveAudioImporterFailure()
                }
            }
            .background {
                MacPracticeWindowCloseGuard(finishPractice: finishPracticeForWindowClose)
                    .frame(width: 0, height: 0)
            }
        }
    }

    private var navigationPath: Binding<[MacLibraryRoute]> {
        Binding(
            get: { path },
            set: { requestedPath in
                guard path.contains(where: { $0.isPractice }), requestedPath != path else {
                    path = requestedPath
                    return
                }
                guard isFinishingPracticeNavigation == false else { return }
                isFinishingPracticeNavigation = true
                Task { @MainActor in
                    defer { isFinishingPracticeNavigation = false }
                    guard await practiceViewModel.returnToLibrary() else { return }
                    path = requestedPath
                }
            }
        )
    }

    private func leavePractice() async {
        guard isFinishingPracticeNavigation == false else { return }
        isFinishingPracticeNavigation = true
        defer { isFinishingPracticeNavigation = false }
        guard await practiceViewModel.returnToLibrary() else { return }
        if path.last?.isPractice == true {
            path.removeLast()
        } else {
            path.removeAll()
        }
    }

    private func finishPracticeForWindowClose() async -> Bool {
        guard practiceViewModel.state != .idle else { return true }
        guard isFinishingPracticeNavigation == false else { return false }
        isFinishingPracticeNavigation = true
        defer { isFinishingPracticeNavigation = false }
        return await practiceViewModel.returnToLibrary()
    }
}

private extension MacLibraryRoute {
    var isPractice: Bool {
        if case .practice = self { return true }
        return false
    }
}

private struct MacLibraryView: View {
    @Bindable var viewModel: MacLibraryViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isInspectorPresented = true

    private var selectedEntry: SongLibraryEntry? {
        viewModel.entries.first(where: { $0.id == viewModel.selectedEntryID })
    }

    private var selectedPresentation: SongLibraryTrackPresentation? {
        guard let selectedEntry,
              let index = viewModel.entries.firstIndex(where: { $0.id == selectedEntry.id })
        else {
            return nil
        }
        return SongLibraryTrackPresentation(entry: selectedEntry, index: index)
    }

    private var selectedDuration: TimeInterval {
        guard let selectedEntry else { return 0 }
        if viewModel.currentListeningEntryID == selectedEntry.id, viewModel.listeningDuration > 0 {
            return viewModel.listeningDuration
        }
        return selectedPresentation?.knownDuration ?? 0
    }

    private var selectedCurrentTime: TimeInterval {
        guard let selectedEntry, viewModel.currentListeningEntryID == selectedEntry.id else { return 0 }
        return viewModel.listeningCurrentTime
    }

    private var selectedProgress: Double {
        selectedDuration > 0 ? selectedCurrentTime / selectedDuration : 0
    }

    private var selectedIsPlaying: Bool {
        guard let selectedEntry else { return false }
        return viewModel.isListeningPlaying(entryID: selectedEntry.id)
    }

    private var requiresAudioImport: Bool {
        selectedEntry?.audioFileName == nil && selectedEntry?.isBundled != true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("曲库")
                        .font(.title2)
                        .bold()
                    Text("导入 MusicXML 或 MXL 后，从这里选择要练习的曲谱。")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("导入曲谱", systemImage: "square.and.arrow.down") {
                    viewModel.presentMusicXMLImporter()
                }
                .buttonStyle(.borderedProminent)
            }

            if viewModel.entries.isEmpty {
                ContentUnavailableView {
                    Label("还没有曲谱", systemImage: "music.note.list")
                } description: {
                    Text("导入 MusicXML 或 MXL 曲谱后开始练习。")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                LibraryRecordCarousel(
                    entries: viewModel.entries,
                    selectedEntryID: viewModel.selectedEntryID,
                    playingEntryID: viewModel.currentListeningEntryID,
                    isPlaying: viewModel.isCurrentListeningPlaying,
                    reduceMotion: reduceMotion,
                    allowsDestructiveActions: viewModel.importState.isActive == false,
                    onSelectEntry: { entryID in
                        Task {
                            await viewModel.selectEntry(entryID)
                        }
                    },
                    onTogglePlayback: { entryID in
                        Task {
                            await viewModel.toggleListening(entryID: entryID)
                        }
                    },
                    onImportMusicXML: viewModel.presentMusicXMLImporter,
                    onImmediateDelete: { entryID in
                        Task {
                            await viewModel.deleteEntry(entryID: entryID)
                        }
                    }
                )
            }

            MacLibraryImportStateView(viewModel: viewModel)

            if let errorMessage = viewModel.errorMessage {
                HStack {
                    Text(errorMessage)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("关闭", action: viewModel.dismissError)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding()
        .safeAreaInset(edge: .bottom) {
            if let selectedEntry, let selectedPresentation {
                LibraryNowPlayingBar(
                    title: selectedPresentation.title,
                    subtitle: selectedPresentation.subtitle,
                    progress: selectedProgress,
                    currentTime: selectedCurrentTime,
                    duration: selectedDuration,
                    isPlaying: viewModel.isListeningPlaying(entryID: selectedEntry.id),
                    canSeek: viewModel.currentListeningEntryID == selectedEntry.id && selectedDuration > 0,
                    canPerformPlaybackAction: selectedEntry.audioFileName != nil || requiresAudioImport,
                    playbackTitle: playbackButtonTitle,
                    playbackSystemImage: playbackButtonSystemImage,
                    onPlayback: toggleSelectedPlayback,
                    onSeek: { progress in
                        viewModel.seekListening(entryID: selectedEntry.id, progress: progress)
                    }
                )
                .background(.bar)
            }
        }
        .inspector(isPresented: $isInspectorPresented) {
            MacLibraryInspectorView(viewModel: viewModel)
                .inspectorColumnWidth(min: 280, ideal: 340, max: 400)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(
                    isInspectorPresented ? "隐藏曲目详情" : "显示曲目详情",
                    systemImage: "sidebar.right"
                ) {
                    isInspectorPresented.toggle()
                }
            }
        }
        .onDisappear {
            viewModel.stopListening()
        }
    }

    private var playbackButtonTitle: String {
        if requiresAudioImport {
            return "导入音频"
        }
        return selectedIsPlaying ? "暂停" : "播放"
    }

    private var playbackButtonSystemImage: String {
        if requiresAudioImport {
            return "waveform.badge.plus"
        }
        return selectedIsPlaying ? "pause.fill" : "play.fill"
    }

    private func toggleSelectedPlayback() {
        guard let selectedEntry else { return }
        Task {
            await viewModel.toggleListening(entryID: selectedEntry.id)
        }
    }
}

private struct MacLibraryInspectorView: View {
    @Bindable var viewModel: MacLibraryViewModel

    private var selectedEntry: SongLibraryEntry? {
        viewModel.entries.first(where: { $0.id == viewModel.selectedEntryID })
    }

    var body: some View {
        Form {
            if let selectedEntry {
                Section("当前曲目") {
                    LabeledContent("名称", value: selectedEntry.displayName)
                    LabeledContent("曲谱", value: selectedEntry.musicXMLFileName)
                    LabeledContent(
                        "音频",
                        value: selectedEntry.audioFileName == nil ? "尚未绑定" : "已绑定"
                    )
                }

                Section("练习") {
                    NavigationLink(value: MacLibraryRoute.practice(selectedEntry.id)) {
                        Label("开始 MIDI 练习", systemImage: "play.fill")
                    }
                }

                if selectedEntry.isBundled != true {
                    Section("音频") {
                        Button(
                            selectedEntry.audioFileName == nil ? "绑定音频" : "替换音频",
                            systemImage: selectedEntry.audioFileName == nil
                                ? "waveform.badge.plus"
                                : "arrow.triangle.2.circlepath"
                        ) {
                            viewModel.presentAudioImporter(for: selectedEntry.id)
                        }
                        .disabled(viewModel.importState.isActive)
                    }

                    Section("危险操作") {
                        Button("删除曲目", systemImage: "trash", role: .destructive) {
                            Task {
                                await viewModel.deleteEntry(entryID: selectedEntry.id)
                            }
                        }
                        .disabled(viewModel.importState.isActive)
                    }
                }
            } else {
                ContentUnavailableView(
                    "未选择曲目",
                    systemImage: "music.note.list",
                    description: Text("从唱片架选择一首曲目以查看详情和操作。")
                )
            }
        }
        .formStyle(.grouped)
    }
}

private struct MacLibraryImportStateView: View {
    @Bindable var viewModel: MacLibraryViewModel

    var body: some View {
        switch viewModel.importState {
        case .idle:
            EmptyView()
        case let .staging(count):
            ProgressView("正在暂存 \(count) 个曲谱")
        case .processing(_, let index, let count):
            ProgressView("正在导入第 \(index) / \(count) 个曲谱")
        case .awaitingConfirmation(let pending, _, _):
            VStack(alignment: .leading, spacing: 8) {
                Text("\(pending.fileName) 与现有曲谱冲突。")
                HStack {
                    Button("确认替换") {
                        Task {
                            await viewModel.confirmPendingImport(operationID: pending.id)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    Button("取消导入") {
                        Task {
                            await viewModel.cancelPendingImport(operationID: pending.id)
                        }
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("导入冲突")
        case .itemFailure(let failure, _, _):
            HStack {
                Text("\(failure.fileName)：\(failure.message)")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("继续") {
                    Task {
                        await viewModel.continueAfterImportFailure()
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("导入失败")
        }
    }
}

private struct MacLibraryUnavailableView: View {
    let title: String
    let message: String
    let retry: @MainActor () async -> Void

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("重新尝试", systemImage: "arrow.clockwise") {
                Task {
                    await retry()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
