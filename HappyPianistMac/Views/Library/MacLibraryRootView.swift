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
                if let selectedEntryID = viewModel.selectedEntryID {
                    NavigationLink(value: MacLibraryRoute.practice(selectedEntryID)) {
                        Label("开始 MIDI 练习", systemImage: "play.fill")
                    }
                    .buttonStyle(.bordered)
                }
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
        .onDisappear {
            viewModel.stopListening()
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
