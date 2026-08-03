import Library
import MusicXML
import Observation
import SwiftUI
import UniformTypeIdentifiers

private enum MacLibraryRoute: Hashable {
    case midiSettings
    case practice(UUID)
}

struct MacLibraryRootView: View {
    @Bindable var viewModel: MacLibraryViewModel
    @Bindable var midiSettingsViewModel: MIDISettingsViewModel
    @Bindable var practiceViewModel: MacPracticeViewModel

    var body: some View {
        NavigationStack {
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
                case .midiSettings:
                    MIDISettingsView(viewModel: midiSettingsViewModel)
                case let .practice(songID):
                    MacPracticeView(songID: songID, viewModel: practiceViewModel)
                }
            }
            .toolbar {
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
        }
    }
}

private struct MacLibraryView: View {
    @Bindable var viewModel: MacLibraryViewModel

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
                List(viewModel.entries) { entry in
                    Button {
                        Task {
                            await viewModel.selectEntry(entry.id)
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(entry.displayName)
                                    .foregroundStyle(.primary)
                                Text(entry.musicXMLFileName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if viewModel.selectedEntryID == entry.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.tint)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(entry.displayName)
                    .accessibilityValue(viewModel.selectedEntryID == entry.id ? "已选择" : "未选择")
                }
                .scrollIndicators(.hidden)
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
