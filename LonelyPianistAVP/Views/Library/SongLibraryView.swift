import SwiftUI

struct SongLibraryView: View {
    @Bindable var viewModel: SongLibraryViewModel

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
                }
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
                    viewModel.didTapStartPractice(entryID: entry.id)
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
