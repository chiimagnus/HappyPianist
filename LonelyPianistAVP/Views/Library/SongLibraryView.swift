import SwiftUI
import UniformTypeIdentifiers

struct SongLibraryView: View {
    @Bindable var viewModel: SongLibraryViewModel
    let navigationPath: Binding<[MainFlowRoute]>
    @State private var isImporterPresented = false

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
        .onAppear {
            viewModel.reload()
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
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.displayName)
                        .font(.headline)
                    Text(entry.importedAt, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("开始练习") {
                    if viewModel.preparePractice(entryID: entry.id) {
                        navigationPath.wrappedValue.append(.practice)
                    }
                }
                .buttonStyle(.bordered)
            }
            .padding(.vertical, 2)
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
