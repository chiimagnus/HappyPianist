import SwiftUI
import UniformTypeIdentifiers

struct SongLibraryView: View {
    @Bindable var viewModel: SongLibraryViewModel
    let navigationPath: Binding<[MainFlowRoute]>
    @State private var isImporterPresented = false
    @State private var isAudioImporterPresented = false
    @State private var pendingAudioBindingEntryID: UUID?
    @State private var pendingDeletionEntryID: UUID?

    private var audioImporterTypes: [UTType] {
        var types: [UTType] = []
        if let mp3Type = UTType(filenameExtension: "mp3") {
            types.append(mp3Type)
        }
        if let m4aType = UTType(filenameExtension: "m4a") {
            types.append(m4aType)
        }
        return types.isEmpty ? [.audio] : types
    }

    init(
        viewModel: SongLibraryViewModel,
        navigationPath: Binding<[MainFlowRoute]> = .constant([])
    ) {
        self.viewModel = viewModel
        self.navigationPath = navigationPath
    }

    var body: some View {
        Group {
            if viewModel.entries.isEmpty {
                emptyState
            } else {
                songList
            }
        }
        .navigationTitle("乐曲库")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("导入 MusicXML") {
                    viewModel.didTapImportMusicXML()
                    isImporterPresented = true
                }
            }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.xml, .musicXML],
            allowsMultipleSelection: true
        ) { result in
            do {
                let urls = try result.get()
                viewModel.importMusicXML(from: urls)
            } catch {
                viewModel.errorMessage = "导入失败：\(error.localizedDescription)"
            }
        }
        .fileImporter(
            isPresented: $isAudioImporterPresented,
            allowedContentTypes: audioImporterTypes,
            allowsMultipleSelection: false
        ) { result in
            do {
                let urls = try result.get()
                guard
                    let entryID = pendingAudioBindingEntryID,
                    let audioURL = urls.first
                else {
                    return
                }

                let ext = audioURL.pathExtension.lowercased()
                guard ext == "mp3" || ext == "m4a" else {
                    viewModel.errorMessage = "仅支持导入 mp3 或 m4a 音频文件。"
                    pendingAudioBindingEntryID = nil
                    return
                }

                viewModel.bindAudio(entryID: entryID, from: audioURL)
            } catch {
                viewModel.errorMessage = "导入音频失败：\(error.localizedDescription)"
            }

            pendingAudioBindingEntryID = nil
        }
        .onAppear {
            viewModel.reload()
        }
        .onDisappear {
            viewModel.stopListening()
        }
        .alert(
            "提示",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { isPresented in
                    if isPresented == false {
                        viewModel.dismissError()
                    }
                }
            )
        ) {
            Button("好") {
                viewModel.dismissError()
            }
        } message: {
            Text(viewModel.errorMessage ?? "未知错误")
        }
        .confirmationDialog(
            "确认删除该曲目？",
            isPresented: Binding(
                get: { pendingDeletionEntryID != nil },
                set: { isPresented in
                    if isPresented == false {
                        pendingDeletionEntryID = nil
                    }
                }
            )
        ) {
            if let entryID = pendingDeletionEntryID {
                Button("删除", role: .destructive) {
                    viewModel.deleteEntry(entryID: entryID)
                    pendingDeletionEntryID = nil
                }
            }
            Button("取消", role: .cancel) {
                pendingDeletionEntryID = nil
            }
        } message: {
            Text("删除后将移除曲谱文件及已绑定音频文件，且无法撤销。")
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("乐曲库为空", systemImage: "music.note.list")
        } description: {
            Text("先导入 MusicXML 开始你的练习旅程。")
        } actions: {
            Button("导入 MusicXML") {
                viewModel.didTapImportMusicXML()
                isImporterPresented = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var songList: some View {
        List(viewModel.entries) { entry in
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.displayName)
                            .font(.headline)
                        if entry.isBundled == true {
                            Text("内置曲目")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(entry.importedAt, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button("开始练习") {
                        if viewModel.preparePractice(entryID: entry.id) {
                            navigationPath.wrappedValue.append(.practice)
                        }
                    }
                    .buttonStyle(.bordered)
                }

                HStack(spacing: 8) {
                    if entry.audioFileName == nil {
                        Text("(无音频)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if entry.isBundled != true {
                            Button("导入音频") {
                                pendingAudioBindingEntryID = entry.id
                                isAudioImporterPresented = true
                            }
                            .buttonStyle(.bordered)
                        }
                    } else {
                        Button(viewModel.isListeningPlaying(entryID: entry.id) ? "暂停" : "聆听") {
                            viewModel.didTapListen(entryID: entry.id)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(.vertical, 2)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if entry.isBundled != true {
                    Button("删除", role: .destructive) {
                        pendingDeletionEntryID = entry.id
                    }
                }
            }
        }
    }
}

#Preview {
    let appModel = AppModel()
    let viewModel = SongLibraryViewModel(appModel: appModel)
    return NavigationStack {
        SongLibraryView(viewModel: viewModel)
    }
}
