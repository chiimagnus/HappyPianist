import Diagnostics
import Library
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
    @State private var deletionEntry: SongLibraryEntry?

    var body: some View {
        Group {
            if viewModel.entries.isEmpty {
                ContentUnavailableView {
                    Label("还没有曲谱", systemImage: "record.circle")
                } description: {
                    Text("导入 MusicXML、XML 或 MXL 曲谱后开始练习。")
                } actions: {
                    Button("导入曲谱", systemImage: "square.and.arrow.down") {
                        viewModel.presentMusicXMLImporter()
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if let selectedEntry {
                VStack(spacing: 0) {
                    MacLibraryRecordShelfView(
                        entries: viewModel.entries,
                        selectedEntryID: viewModel.selectedEntryID,
                        playingEntryID: viewModel.currentListeningEntryID,
                        isPlaying: viewModel.isListeningPlaying(entryID: selectedEntry.id),
                        allowsDestructiveActions: viewModel.importState.isActive == false,
                        onSelectEntry: selectEntry,
                        onTogglePlayback: togglePlayback,
                        onImportAudio: viewModel.presentAudioImporter,
                        onDelete: { entryID in
                            deletionEntry = entry(for: entryID)
                        }
                    )

                    HStack(alignment: .bottom, spacing: 24) {
                        MacLibraryTrackInfoView(
                            entry: selectedEntry,
                            isPlaying: viewModel.isListeningPlaying(entryID: selectedEntry.id),
                            isImporting: viewModel.importState.isActive,
                            onTogglePlayback: { togglePlayback(selectedEntry.id) },
                            onImportAudio: { viewModel.presentAudioImporter(for: selectedEntry.id) },
                            onDelete: { deletionEntry = selectedEntry }
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)

                        NavigationLink(value: MacLibraryRoute.practice(selectedEntry.id)) {
                            Label("开始 MIDI 练习", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.importState.isActive)
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 28)
                }
            }
        }
        .navigationTitle("曲库")
        .frame(minWidth: 760, idealWidth: 1080, minHeight: 620, idealHeight: 720)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("导入曲谱", systemImage: "square.and.arrow.down") {
                    viewModel.presentMusicXMLImporter()
                }
                .disabled(viewModel.importState.isActive)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if viewModel.importState.isActive {
                MacLibraryImportStateView(viewModel: viewModel)
                    .padding(.horizontal)
                    .padding(.bottom, 12)
                    .background(.bar)
            }
        }
        .alert(
            "无法完成操作",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { isPresented in
                    if isPresented == false {
                        viewModel.dismissError()
                    }
                }
            )
        ) {
            Button("好", action: viewModel.dismissError)
        } message: {
            Text(viewModel.errorMessage ?? "未知错误")
        }
        .confirmationDialog(
            "删除“\(deletionEntry?.displayName ?? "")”？",
            isPresented: Binding(
                get: { deletionEntry != nil },
                set: { isPresented in
                    if isPresented == false {
                        deletionEntry = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("删除曲目", role: .destructive) {
                guard let deletionEntry else { return }
                self.deletionEntry = nil
                Task {
                    await viewModel.deleteEntry(entryID: deletionEntry.id)
                }
            }
            Button("取消", role: .cancel) {
                deletionEntry = nil
            }
        } message: {
            Text("曲谱、关联音频和练习进度将被删除。")
        }
        .onDisappear {
            viewModel.stopListening()
        }
    }

    private var selectedEntry: SongLibraryEntry? {
        guard let selectedEntryID = viewModel.selectedEntryID else { return nil }
        return viewModel.entries.first(where: { $0.id == selectedEntryID })
    }

    private func entry(for entryID: UUID) -> SongLibraryEntry? {
        viewModel.entries.first(where: { $0.id == entryID })
    }

    private func selectEntry(_ entryID: UUID) {
        Task {
            await viewModel.selectEntry(entryID)
        }
    }

    private func togglePlayback(_ entryID: UUID) {
        Task {
            await viewModel.toggleListening(entryID: entryID)
        }
    }
}

private struct MacLibraryImportStateView: View {
    @Bindable var viewModel: MacLibraryViewModel

    var body: some View {
        switch viewModel.importState {
        case .idle:
            EmptyView()
        case let .staging(count):
            importStatus("正在暂存 \(count) 个曲谱")
        case .processing(_, let index, let count):
            importStatus("正在导入第 \(index) / \(count) 个曲谱")
        case .awaitingConfirmation(let pending, _, _):
            importConflict(pending)
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

    private func importStatus(_ title: String) -> some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(title)
                .font(.callout)
            Spacer()
        }
        .padding(12)
        .accessibilityElement(children: .combine)
    }

    private func importConflict(_ pending: SongLibraryPendingImport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("发现同名曲谱", systemImage: "exclamationmark.triangle")
                .font(.callout)
            Text("\(pending.fileName) 与现有曲谱冲突。")
                .font(.caption)
                .foregroundStyle(.secondary)
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
        .padding(12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("导入冲突")
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
