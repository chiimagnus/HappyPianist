import SwiftUI

struct TakeLibraryRowView: View {
    let take: RecordingTake
    let metadataText: String
    let isPlaying: Bool
    let isDisabled: Bool
    let onPlayPause: () -> Void
    let onRename: () -> Void
    let onExport: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(take.name)
                    .font(.body)
                Text(metadataText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(
                isPlaying ? "暂停录制回放" : "播放录制",
                systemImage: isPlaying ? "pause.circle.fill" : "play.circle.fill",
                action: onPlayPause
            )
            .font(.title2)
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .buttonBorderShape(.roundedRectangle)
            .disabled(isDisabled || take.events.isEmpty)

            Menu {
                Button("重命名", systemImage: "pencil", action: onRename)
                Button("导出 MIDI...", systemImage: "square.and.arrow.up", action: onExport)
                Button("删除", systemImage: "trash", role: .destructive, action: onDelete)
            } label: {
                Label("更多操作", systemImage: "ellipsis.circle")
                    .font(.title3)
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .buttonBorderShape(.roundedRectangle)
        }
        .padding(.vertical, 4)
    }
}
