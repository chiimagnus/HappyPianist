import SwiftUI

struct SongLibraryEmptyView: View {
    let onImport: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("乐曲库为空", systemImage: "record.circle")
                .foregroundStyle(LibraryDesignTokens.text)
        } description: {
            Text("导入 MusicXML 后，曲谱会以黑胶唱片的形式出现在这里。")
                .foregroundStyle(LibraryDesignTokens.secondaryText)
        } actions: {
            Button("导入 MusicXML", systemImage: "plus", action: onImport)
                .buttonStyle(.borderedProminent)
                .tint(LibraryDesignTokens.accent)
                .foregroundStyle(LibraryDesignTokens.accentForeground)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
