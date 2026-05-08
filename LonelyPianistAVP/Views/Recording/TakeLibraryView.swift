import SwiftUI
import UniformTypeIdentifiers

struct TakeLibraryView: View {
    let takes: [RecordingTake]
    let playbackController: TakePlaybackController
    var isRecording: Bool = false
    var errorMessage: String?
    let onErrorDismiss: () -> Void
    let onRename: (UUID, String) -> Void
    let onDelete: (UUID) -> Void
    let onClearAll: () -> Void

    @State private var sliderValue: Double = 0
    @State private var isDraggingSlider = false
    @State private var renameTarget: RecordingTake?
    @State private var renameText = ""
    @State private var timer: Timer?
    @State private var exportDocument: MIDIFileDocument?
    @State private var exportFileName: String = ""
    @State private var exportError: String?
    @State private var isClearAllConfirmationPresented = false

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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("清空全部录制", systemImage: "trash", role: .destructive) {
                        isClearAllConfirmationPresented = true
                    }
                    .disabled(takes.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .buttonBorderShape(.roundedRectangle)
                .hoverEffect()
                .disabled(isRecording)
            }
        }
        .confirmationDialog(
            "清空全部录制？",
            isPresented: $isClearAllConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("清空", role: .destructive) {
                playbackController.stop()
                sliderValue = 0
                onClearAll()
            }
        } message: {
            Text("此操作会删除所有录制，且不可恢复。")
        }
        .fileExporter(
            isPresented: .init(
                get: { exportDocument != nil },
                set: { if !$0 { exportDocument = nil } }
            ),
            document: exportDocument,
            contentType: .midi,
            defaultFilename: exportFileName
        ) { _ in }
        .alert("错误", isPresented: .init(
            get: { errorMessage != nil || exportError != nil },
            set: { if !$0 { onErrorDismiss(); exportError = nil } }
        )) {
            Button("知道了") { onErrorDismiss(); exportError = nil }
        } message: {
            Text(errorMessage ?? exportError ?? "")
        }
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
            .disabled(isRecording)

            Menu {
                Button("重命名", systemImage: "pencil") {
                    renameText = take.name
                    renameTarget = take
                }
                Button("导出 MIDI...", systemImage: "square.and.arrow.up") {
                    exportMIDI(take)
                }
                Button("删除", systemImage: "trash", role: .destructive) {
                    if playbackController.currentTakeID == take.id {
                        playbackController.stop()
                        sliderValue = 0
                    }
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
            .disabled(playbackController.currentTakeID == nil || isRecording)

            Button {
                playbackController.stop()
                sliderValue = 0
            } label: {
                Image(systemName: "stop.fill")
                    .font(.title3)
            }
            .buttonBorderShape(.roundedRectangle)
            .hoverEffect()
            .disabled(playbackController.currentTakeID == nil || isRecording)

            Slider(value: $sliderValue, in: 0...max(0.001, totalDuration)) { editing in
                isDraggingSlider = editing
                if editing == false {
                    if playbackController.isPlaying {
                        try? playbackController.seek(toSeconds: sliderValue)
                    } else {
                        playbackController.pausePositionSeconds = max(0, sliderValue)
                    }
                }
            }
            .disabled(playbackController.currentTakeID == nil || isRecording)

            Text(formatDuration(isDraggingSlider ? sliderValue : playbackController.currentSeconds()))
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
            Task { @MainActor in
                guard isDraggingSlider == false else { return }
                sliderValue = playbackController.currentSeconds()
            }
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

    private func exportMIDI(_ take: RecordingTake) {
        let adapter = RecordingTakeSequenceAdapter()
        do {
            let sequence = try adapter.buildSequence(from: take)
            exportDocument = MIDIFileDocument(data: sequence.midiData)
            let sanitizedName = take.name.replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
            exportFileName = "\(sanitizedName).mid"
        } catch {
            exportError = "导出失败：\(error.localizedDescription)"
        }
    }
}
