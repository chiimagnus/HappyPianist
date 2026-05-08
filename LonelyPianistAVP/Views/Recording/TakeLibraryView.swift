import SwiftUI

struct TakeLibraryView: View {
    let takes: [RecordingTake]
    let playbackController: TakePlaybackController
    let onRename: (UUID, String) -> Void
    let onDelete: (UUID) -> Void
    let onClearAll: () -> Void

    @State private var sliderValue: Double = 0
    @State private var isDraggingSlider = false
    @State private var renameTarget: RecordingTake?
    @State private var renameText = ""
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 0) {
            if takes.isEmpty {
                ContentUnavailableView(
                    "没有录制",
                    systemImage: "mic.slash",
                    description: Text("在练习时点击录制按钮开始录制。")
                )
            } else {
                List {
                    ForEach(takes) { take in
                        takeRow(take)
                    }
                }
                .listStyle(.plain)
            }

            Divider()

            nowPlayingBar
        }
        .onAppear { startTimer() }
        .onDisappear { stopTimer() }
        .alert("重命名", isPresented: .init(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("名称", text: $renameText)
            Button("确定") {
                if let target = renameTarget, renameText.isEmpty == false {
                    onRename(target.id, renameText)
                }
                renameTarget = nil
            }
            Button("取消", role: .cancel) {
                renameTarget = nil
            }
        }
    }

    private func takeRow(_ take: RecordingTake) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(take.name)
                    .font(.body)
                Text("\(formatDuration(take.durationSeconds)) · \(formatDate(take.createdAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                playOrPause(take)
            } label: {
                Image(systemName: isPlayingTake(take) ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)
            }
            .buttonBorderShape(.roundedRectangle)
            .hoverEffect()

            Menu {
                Button("重命名", systemImage: "pencil") {
                    renameText = take.name
                    renameTarget = take
                }
                Button("删除", systemImage: "trash", role: .destructive) {
                    onDelete(take.id)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
            }
            .buttonBorderShape(.roundedRectangle)
            .hoverEffect()
        }
        .padding(.vertical, 4)
    }

    private var nowPlayingBar: some View {
        HStack(spacing: 12) {
            Button {
                if playbackController.isPlaying {
                    playbackController.pause()
                } else {
                    try? playbackController.resume()
                }
            } label: {
                Image(systemName: playbackController.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
            }
            .buttonBorderShape(.roundedRectangle)
            .hoverEffect()
            .disabled(playbackController.currentTakeID == nil)

            Button {
                playbackController.stop()
                sliderValue = 0
            } label: {
                Image(systemName: "stop.fill")
                    .font(.title3)
            }
            .buttonBorderShape(.roundedRectangle)
            .hoverEffect()
            .disabled(playbackController.currentTakeID == nil)

            Slider(value: $sliderValue, in: 0...max(1, totalDuration)) { editing in
                isDraggingSlider = editing
                if editing == false {
                    try? playbackController.seek(toSeconds: sliderValue)
                }
            }
            .disabled(playbackController.currentTakeID == nil)

            Text(formatDuration(playbackController.currentSeconds()))
                .monospacedDigit()
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 45, alignment: .trailing)

            Text("/ \(formatDuration(totalDuration))")
                .monospacedDigit()
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 45, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var totalDuration: TimeInterval {
        guard let takeID = playbackController.currentTakeID else { return 0 }
        return takes.first(where: { $0.id == takeID })?.durationSeconds ?? 0
    }

    private func isPlayingTake(_ take: RecordingTake) -> Bool {
        playbackController.currentTakeID == take.id && playbackController.isPlaying
    }

    private func playOrPause(_ take: RecordingTake) {
        if playbackController.currentTakeID == take.id {
            if playbackController.isPlaying {
                playbackController.pause()
            } else {
                try? playbackController.resume()
            }
        } else {
            try? playbackController.play(take: take)
        }
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            guard isDraggingSlider == false else { return }
            sliderValue = playbackController.currentSeconds()
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
